# frozen_string_literal: true

require "rails_helper"

RSpec.describe Findings::ForReport do
  let(:company) { create(:company, :onboarded) }
  # These examples are about grouping and totals; pooling has its own below.
  before { company.update!(settings: company.settings.merge("report_small_roles" => "show")) }

  def finding(role:, department: "Procurement", hours: nil, **attrs)
    employee = attrs.delete(:employee) || create(:employee, company: company, role_title: role, department: department)
    company.findings.create!(
      {
        employee: employee, source_key: SecureRandom.hex(4), department: department, role_title: role,
        area: "work #{SecureRandom.hex(2)}", friction: "It snags",
        annual_hours_min: hours&.first, annual_hours_max: hours&.last
      }.merge(attrs)
    )
  end

  it "groups by department and role, and every total adds up to its rows" do
    finding(role: "Procurement Officer", hours: [160, 240])
    finding(role: "Procurement Officer", hours: [120, 180])
    finding(role: "Buyer", hours: [40, 85])
    finding(role: "Accounts Payable Clerk", department: "Finance", hours: [240, 240])

    view = described_class.call(company: company)
    procurement = view["departments"].find { |d| d["name"] == "Procurement" }
    officer = procurement["roles"].find { |r| r["title"] == "Procurement Officer" }

    expect(officer.values_at("hours_min", "hours_max")).to eq([280, 420])
    expect(procurement.values_at("hours_min", "hours_max")).to eq([320, 505])
    expect(view["totals"]).to include("findings" => 4, "quantified" => 4, "roles" => 3, "departments" => 2,
                                      "hours_min" => 560, "hours_max" => 745)
  end

  it "leaves out hidden and merged findings, and counts the people merged in" do
    kept = finding(role: "Procurement Officer", hours: [120, 180])
    finding(role: "Procurement Officer", hours: [160, 160], status: "merged", merged_into: kept)
    finding(role: "Procurement Officer", hours: [50, 50], status: "hidden")

    view = described_class.call(company: company)
    row = view["departments"].first["roles"].first["findings"]

    expect(row.size).to eq(1)
    expect(row.first["people"]).to eq(2)
    expect(view["totals"].values_at("hours_min", "hours_max")).to eq([120, 180])
  end

  it "withholds an unreviewed finding about a role one person holds, until it is approved" do
    lone = finding(role: "HR Officer", department: "HR", hours: [190, 195], single_occupant_role: true)

    expect(described_class.call(company: company)["totals"]["findings"]).to eq(0)
    expect(described_class.call(company: company)["withheld"]).to eq(1)

    lone.update!(status: "approved")
    expect(described_class.call(company: company)["totals"]["findings"]).to eq(1)
  end

  it "lists waiting as a delay, never as hours" do
    finding(role: "HR Officer", department: "HR", effort_type: "waiting", duration_as_said: "sometimes for weeks")

    view = described_class.call(company: company)
    expect(view["delays"]).to eq([{ "title" => view["delays"].first["title"], "role" => "HR Officer",
                                    "department" => "HR", "duration" => "sometimes for weeks" }])
    expect(view["totals"]["hours_min"]).to be_nil
  end

  describe "roles held by one person" do
    before { company.update!(settings: company.settings.merge("report_small_roles" => "pool")) }

    it "never shows one by name: pooled in the department, else across the company" do
      finding(role: "Procurement Officer", hours: [160, 240])
      finding(role: "Procurement Officer", hours: [120, 180])
      finding(role: "AP Clerk", department: "Finance", hours: [240, 240])
      finding(role: "Finance Manager", department: "Finance", hours: [190, 195])
      finding(role: "HR Officer", department: "HR", hours: [95, 100])

      view = described_class.call(company: company)
      titles = view["departments"].to_h { |d| [d["name"], d["roles"].map { |r| r["title"] }] }

      expect(titles).to eq("Procurement" => ["Procurement Officer"], "Finance" => ["Other roles"],
                           "Across the company" => ["Roles across the company"])
      across = view["departments"].find { |d| d["name"] == "Across the company" }["roles"].first["findings"].first
      expect(across.values_at("role", "department")).to eq([nil, nil])
      expect(view["totals"].values_at("hours_min", "hours_max")).to eq([805, 955])
      expect(view.to_json).not_to include("HR Officer", "AP Clerk", "Finance Manager")
    end
  end

  describe "value at benchmark rates" do
    it "shows nothing in money while no rate is agreed" do
      finding(role: "Buyer", hours: [100, 150])
      view = described_class.call(company: company)
      expect(view["totals"]).not_to have_key("value_min")
      expect(view["rates"]).to eq([])
    end

    it "values capacity at the role family's rate, or the default, rounded outward" do
      BenchmarkRate.create!(version: "2026-10", market: "AE", role_family: "procurement", currency: "AED",
                            hourly_rate_min: 90, hourly_rate_max: 110, effective_from: Date.current - 1)
      BenchmarkRate.create!(version: "2026-10", market: "AE", role_family: "default", currency: "AED",
                            hourly_rate_min: 60, hourly_rate_max: 80, effective_from: Date.current - 1)
      finding(role: "Buyer", hours: [100, 150])
      finding(role: "Clerk", department: "Finance", hours: [240, 240])

      view = described_class.call(company: company)
      rows = view["departments"].flat_map { |d| d["roles"].flat_map { |r| r["findings"] } }.index_by { |f| f["role"] }

      expect(rows["Buyer"].values_at("value_min", "value_max", "currency")).to eq([9000, 16_500, "AED"])
      expect(rows["Clerk"].values_at("value_min", "value_max")).to eq([14_400, 19_200])
      expect(view["totals"].values_at("value_min", "value_max")).to eq([23_400, 35_700])
      expect(view["rates"].map { |r| r["role_family"] }).to contain_exactly("procurement", "default")
    end
  end
end
