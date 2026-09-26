# frozen_string_literal: true

require "rails_helper"

RSpec.describe Findings::ForReport do
  let(:company) { create(:company, :onboarded) }

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
end
