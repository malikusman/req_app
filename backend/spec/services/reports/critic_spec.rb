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
      "frequency" => "every day", "duration" => "an hour", "effort_type" => "active",
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

  it "blocks products and published ideas, which are Stage 2's" do
    snapshot["tools_catalog"] = { "curated_matches" => [{ "name" => "Bill.com" }] }
    snapshot["agentic_ideas"] = [{ "title" => "Invoice Intake Agent" }]
    checks = described_class.call(report: report)
    expect(checks.map { |c| c[:code] }).to include("names_vendors", "shows_ideas")
    expect(described_class.blocking?(checks)).to be(true)
  end

  it "blocks a section added from a Stage 2 template" do
    report.report_section_overrides.create!(consultant_user: create(:consultant_user), action: "add",
                                            section_key: "implementation", title: "Implementation plan",
                                            body: "## Owners and effort", published: true)
    expect(codes).to include("stage2_section")
  end

  it "blocks an hours figure in the consultant's text that the findings do not carry" do
    consultant = create(:consultant_user)
    report.report_section_overrides.create!(consultant_user: consultant, action: "edit", section_key: "executive_summary",
                                            body: "Clerks spend 240–490 hours a year re-keying, about 2 hours a day.",
                                            published: true)
    checks = described_class.call(report: report)
    figures = checks.find { |c| c[:code] == "unreconciled_figures" }
    expect(figures[:severity]).to eq("block")
    expect(figures[:message]).to include("490 hours")
    expect(figures[:message]).not_to include("240 hours")
    # "2 hours a day" is how long one piece takes — said, not computed — so it is
    # shown to the consultant, not blocked.
    quoted = checks.find { |c| c[:code] == "ungrounded_figures" }
    expect(quoted).to include(severity: "warn")
    expect(quoted[:message]).to include("2 hours")
  end

  it "does not check the consultant's edit of a section they hid" do
    consultant = create(:consultant_user)
    report.report_section_overrides.create!(consultant_user: consultant, action: "edit", section_key: "executive_summary",
                                            body: "Clerks spend 490 hours a year re-keying.", published: true)
    report.report_section_overrides.create!(consultant_user: consultant, action: "hide", section_key: "executive_summary",
                                            published: true)
    expect(codes).not_to include("unreconciled_figures")
  end

  it "blocks a finding that names no work" do
    row.merge!("frequency" => nil, "duration" => nil)
    expect(codes).to include("not_specific")
  end

  it "lets a wait through without how often or how long — how long it lasts is the finding" do
    row.merge!("frequency" => nil, "duration" => nil, "effort_type" => "waiting")
    expect(codes).not_to include("not_specific")
  end

  describe "duplicates" do
    let!(:twin) do
      company.findings.create!(employee: employee, source_key: "k2", area: "supplier chasing", department: "finance",
                               role_title: "AP Clerk", friction: "Buyers are chased by email", status: "approved",
                               duration_min: 10, duration_max: 15, duration_unit: "minutes")
    end
    let(:twin_row) do
      { "id" => twin.id, "title" => "Supplier chasing", "friction" => "Buyers are chased by email",
        "frequency" => "per invoice", "duration" => "10 to 15 minutes", "effort_type" => "active" }
    end

    before { findings_view["departments"].first["roles"].first["findings"] << twin_row }

    it "warns when one person's two findings take the very same time" do
      finding.update!(duration_min: 10, duration_max: 15, duration_unit: "minutes")
      checks = described_class.call(report: report)
      expect(checks.find { |c| c[:code] == "possible_duplicate" }).to include(severity: "warn")
    end

    it "leaves two people's own work alone, however alike" do
      twin.update!(employee: create(:employee, company: company), area: "invoice entry", title: "Invoice entry")
      twin_row["title"] = "Invoice entry"
      finding.update!(duration_min: 10, duration_max: 15, duration_unit: "minutes")
      expect(codes).not_to include("possible_duplicate")
    end

    it "warns when several findings give the same cause" do
      twin.update!(employee: create(:employee, company: company))
      row["cause"] = "Supplier invoices arrive in different layouts."
      twin_row["cause"] = "Supplier invoices arrive in different layouts!"
      expect(codes).to include("possible_duplicate")
    end
  end

  describe "coverage" do
    before do
      snapshot["coverage"] = { "departments" => [{ "department" => "finance", "invited" => 2, "completed" => 2 },
                                                 { "department" => "logistics", "invited" => 1, "completed" => 0 }],
                               "not_interviewed" => [] }
    end

    it "blocks a company-wide conclusion when a department went unheard" do
      snapshot["narrative"] = { "governing_thought" => "Re-keying slows work across the company." }
      expect(codes).to include("overreach_coverage")
    end

    it "lets a negated one through" do
      snapshot["narrative"] = { "governing_thought" => "This is not yet a view across the company." }
      expect(codes).not_to include("overreach_coverage")
    end

    it "never reads the report's own labels as a conclusion" do
      body.replace("Roles across the company · About 240 hours a year go into the work people described.")
      expect(codes).not_to include("overreach_coverage")
    end

    it "warns when the prose describes a department nobody spoke for" do
      snapshot["narrative"] = { "governing_thought" => "Logistics re-keys every delivery note." }
      expect(described_class.call(report: report).find { |c| c[:code] == "uncovered_department" }).to include(severity: "warn")
    end

    it "lets the same claim through once every department took part" do
      snapshot["coverage"]["departments"].last["completed"] = 1
      snapshot["narrative"] = { "governing_thought" => "Re-keying slows work across the company." }
      expect(codes).not_to include("overreach_coverage", "uncovered_department")
    end
  end

  it "blocks internal rates and Mjadi's own terms" do
    body.replace("Valued at AED 85 per hour, within our margin.")
    expect(codes).to include("commercial_data")
  end

  it "leaves the client's own margins and commissions alone" do
    body.replace("The owners want to protect their margins and simplify sales commission runs.")
    expect(codes).not_to include("commercial_data")
  end

  it "passes consultant text that quotes the findings' own figures" do
    report.report_section_overrides.create!(consultant_user: create(:consultant_user), action: "edit",
                                            section_key: "executive_summary",
                                            body: "Clerks spend 240 hours a year re-keying invoices.", published: true)
    expect(codes).not_to include("unreconciled_figures")
  end

  it "warns when a role claims more hours than its people work in a year" do
    role = findings_view["departments"].first["roles"].first
    role.merge!("people" => 1, "hours_min" => 2000, "hours_max" => 2000)
    row.merge!("hours_min" => 2000, "hours_max" => 2000)
    findings_view["departments"].first.merge!("hours_min" => 2000, "hours_max" => 2000)
    findings_view["totals"].merge!("hours_min" => 2000, "hours_max" => 2000)
    checks = described_class.call(report: report)
    expect(checks.find { |c| c[:code] == "role_over_capacity" }&.dig(:severity)).to eq("warn")
  end

  it "warns, without blocking, about overreach and few quantified findings" do
    snapshot["narrative"] = { "governing_thought" => "Manual work severely limits growth." }
    findings_view["totals"].merge!("findings" => 4, "quantified" => 1)
    checks = described_class.call(report: report)
    expect(checks.map { |c| c[:code] }).to include("overreach", "few_hours")
    expect(described_class.blocking?(checks)).to be(false)
  end
end
