# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::ReviewNotesCollector do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user, name: "Alex Expert") }
  let(:report) { create(:report, :ready, company: company) }
  let!(:submitted) do
    create(:report_review, report: report, consultant_user: consultant, company: company,
                           overall_note: "Ready to share.", submitted_at: Time.current, status: "approved")
  end
  let!(:draft) do
    other = create(:consultant_user, name: "Draft Consultant", email: "draft@reqapp.local")
    create(:report_review, report: report, consultant_user: other, company: company, overall_note: "Not ready")
  end

  before do
    create(:report_review_comment, report_review: submitted, consultant_user: consultant,
                                   section_key: "signals", body: "Open comment", resolved: false)
    create(:report_review_comment, report_review: submitted, consultant_user: consultant,
                                   section_key: "patterns", body: "Resolved comment", resolved: true)
  end

  it "includes only submitted reviews and unresolved comments" do
    notes = described_class.call(report: report)
    bodies = notes.map { |n| n["body"] }
    expect(bodies).to include("Ready to share.", "Open comment")
    expect(bodies).not_to include("Not ready", "Resolved comment")
  end

  it "overlays publishable findings with disposition and evidence refs" do
    submitted.report_review_findings.create!(
      consultant_user: consultant,
      finding_type: "executive_conclusion",
      severity: "material",
      disposition: "endorse",
      body: "Evidence supports the readiness claim.",
      evidence_refs: %w[signal:1 pattern:2],
      publishable: true
    )
    submitted.report_review_findings.create!(
      consultant_user: consultant,
      finding_type: "risk",
      severity: "info",
      body: "Draft-only note",
      publishable: false
    )

    overlay = described_class.new(report: report).overlay
    findings = overlay["structured_findings"]

    expect(findings.size).to eq(1)
    expect(findings.first).to include(
      "consultant" => "Alex Expert",
      "disposition" => "endorse",
      "severity" => "material",
      "body" => "Evidence supports the readiness claim.",
      "evidence_refs" => %w[signal:1 pattern:2]
    )
  end
end
