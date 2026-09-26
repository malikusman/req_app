# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::Critic do
  let(:company) { create(:company, :onboarded) }
  let(:employee) { create(:employee, company: company, display_name: "Layla Haddad", role_title: "AP Clerk") }
  let!(:finding) do
    company.findings.create!(employee: employee, source_key: "k1", area: "invoice entry", department: "finance",
                             role_title: "AP Clerk", friction: "Invoices are re-keyed", status: "approved",
                             annual_hours_min: 240, annual_hours_max: 240)
  end
  let(:row) do
    { "id" => finding.id, "title" => "Invoice entry", "friction" => "Invoices are re-keyed", "what_happens_now" => nil,
      "hours_min" => 240, "hours_max" => 240 }
  end
  let(:findings_view) do
    { "totals" => { "findings" => 1, "quantified" => 1, "hours_min" => 240, "hours_max" => 240 },
      "departments" => [{ "name" => "finance", "hours_min" => 240, "hours_max" => 240,
                          "roles" => [{ "title" => "AP Clerk", "hours_min" => 240, "hours_max" => 240, "findings" => [row] }] }] }
  end
  let(:snapshot) { { "company" => { "name" => "Acme" }, "findings" => findings_view } }
  let(:report) { create(:report, company: company, report_snapshot: snapshot, generated_at: 1.hour.ago) }
  let(:body) { +"About 240 hours a year go into the work people described. These hours are capacity, not converted to salary." }

  before do
    allow(Reports::RegenerateWithReviewService).to receive(:render_html) { "<html><body><p>#{body}</p></body></html>" }
  end

  def codes = described_class.call(report: report).map { |c| c[:code] }

  it "passes a report that keeps the rules, including its own disclaimers" do
    expect(described_class.call(report: report)).to be_empty
  end

  it "blocks totals that do not add up to their rows" do
    findings_view["departments"].first["roles"].first["hours_max"] = 300
    expect(codes).to include("unreconciled_totals")
  end

  it "blocks a priority whose hours are not the findings it names" do
    snapshot["priorities"] = [{ "title" => "Re-keying", "finding_ids" => [finding.id], "hours_min" => 240, "hours_max" => 900 }]
    expect(codes).to include("unreconciled_totals")
  end

  it "blocks salary, cuts and money when no benchmark rates exist" do
    body.replace("This frees two FTEs and saves AED 120,000 a year.")
    expect(codes).to include("payroll_language", "money_without_rates")
  end

  it "blocks build detail" do
    body.replace("We would build a bot; the implementation plan runs 6 weeks to deploy.")
    expect(codes).to include("build_detail")
  end

  it "blocks a finding that reads as a quote, and a named person" do
    row["friction"] = "Waiting for their replies frustrates me most"
    body.replace("Layla Haddad said invoices pile up.")
    expect(codes).to include("reads_as_quote", "names_a_person")
  end

  it "blocks findings a consultant hid or flagged after the report was generated" do
    finding.update!(status: "hidden")
    expect(codes).to include("findings_changed")
  end

  it "warns, without blocking, about overreach and few quantified findings" do
    snapshot["narrative"] = { "governing_thought" => "Manual work severely limits growth." }
    findings_view["totals"].merge!("findings" => 4, "quantified" => 1)
    checks = described_class.call(report: report)
    expect(checks.map { |c| c[:code] }).to include("overreach", "few_hours")
    expect(described_class.blocking?(checks)).to be(false)
  end
end
