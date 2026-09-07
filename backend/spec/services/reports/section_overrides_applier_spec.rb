# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::SectionOverridesApplier do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user, name: "Nadia Al-Rashid", headline: "14 yrs ops") }
  let(:snapshot) { { "executive_summary" => "Machine-written summary.", "signals" => [] } }
  let(:report) do
    company.reports.create!(
      version: 2, status: "ready", visibility: "internal_only",
      triggered_by_type: "CompanyUser", triggered_by_id: 1,
      report_snapshot: snapshot, generated_at: Time.current
    )
  end

  def override!(action:, section_key: nil, title: nil, body: nil, anchor: nil)
    report.report_section_overrides.create!(
      consultant_user: consultant, action: action, section_key: section_key,
      title: title, body: body, anchor_section: anchor, published: true
    )
  end

  it "leaves the stored snapshot untouched" do
    override!(action: "hide", section_key: "readiness")

    described_class.call(snapshot: report.report_snapshot, report: report)

    expect(report.reload.report_snapshot).to eq(snapshot)
  end

  it "carries the consultant's credential onto an added section" do
    override!(action: "add", section_key: "risks", title: "Risks and mitigations",
              body: "## Execution risks", anchor: "recommendations")

    custom = described_class.call(snapshot: report.report_snapshot, report: report)
      .dig("section_overrides", "custom")

    expect(custom.first["consultant"]).to eq("Nadia Al-Rashid")
    expect(custom.first["consultant_credential"]).to include("14 yrs ops")
  end

  # A section added from the library carries the library's statement of what the
  # section is for, so the rendered page explains itself.
  it "attaches the library template's purpose to a section added from it" do
    override!(action: "add", section_key: "assumptions_limitations",
              title: "Assumptions and limitations", body: "## What we assumed", anchor: "methodology")

    custom = described_class.call(snapshot: report.report_snapshot, report: report)
      .dig("section_overrides", "custom")

    expect(custom.first["purpose"]).to eq(ReportSectionTemplates.find("assumptions_limitations")["purpose"])
  end

  # A consultant re-adding a section that was already carried forward from the
  # previous version leaves two identical rows, and the deliverable printed the
  # page once per row.
  it "prints an identical added section only once" do
    3.times do
      override!(action: "add", section_key: "risks", title: "Risks and mitigations",
                body: "## Execution risks", anchor: "recommendations")
    end

    custom = described_class.call(snapshot: report.report_snapshot, report: report)
      .dig("section_overrides", "custom")

    expect(custom.size).to eq(1)
  end

  it "keeps two genuinely different sections that share a template key" do
    override!(action: "add", section_key: "risks", title: "Delivery risks",
              body: "## Execution risks", anchor: "recommendations")
    override!(action: "add", section_key: "risks", title: "Commercial risks",
              body: "## Contract exposure", anchor: "recommendations")

    custom = described_class.call(snapshot: report.report_snapshot, report: report)
      .dig("section_overrides", "custom")

    expect(custom.map { |c| c["title"] }).to contain_exactly("Delivery risks", "Commercial risks")
  end

  # The executive summary also feeds the cover subtitle and the contents teaser,
  # so a rewrite has to reach the base field or the cover quotes the AI while
  # page three quotes the expert.
  it "propagates an executive summary rewrite onto the base field" do
    override!(action: "edit", section_key: "executive_summary", body: "The expert's version.")

    result = described_class.call(snapshot: report.report_snapshot, report: report)

    expect(result["executive_summary"]).to eq("The expert's version.")
  end
end
