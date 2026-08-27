# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::SectionOverridesApplier do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user, name: "Dr. Jane Expert") }
  let(:report) do
    create(:report, :ready, company: company).tap do |r|
      r.report_snapshot["executive_summary"] = "Original summary."
    end
  end
  let(:snapshot) { report.report_snapshot }

  it "returns the snapshot unchanged when there are no overrides" do
    result = described_class.call(snapshot: snapshot, report: report)
    expect(result["section_overrides"]).to be_nil
  end

  it "collects hide, edit, and custom-add overrides without mutating the stored snapshot" do
    report.report_section_overrides.create!(consultant_user: consultant, action: "hide", section_key: "readiness")
    report.report_section_overrides.create!(consultant_user: consultant, action: "edit", section_key: "executive_summary",
                                            title: "Revised", body: "Consultant revision.")
    report.report_section_overrides.create!(consultant_user: consultant, action: "add", title: "Risk Register",
                                            body: "Key risks.", anchor_section: "recommendations", position: 1)

    result = described_class.call(snapshot: snapshot, report: report)

    expect(result["section_overrides"]["hidden"]).to include("readiness")
    expect(result.dig("section_overrides", "edits", "executive_summary", "body")).to eq("Consultant revision.")
    custom = result.dig("section_overrides", "custom").first
    expect(custom["title"]).to eq("Risk Register")
    expect(custom["anchor_section"]).to eq("recommendations")
    expect(custom["consultant"]).to eq("Dr. Jane Expert")
    # Stored snapshot object is a copy — original untouched.
    expect(snapshot["section_overrides"]).to be_nil
  end

  it "excludes unpublished overrides" do
    report.report_section_overrides.create!(consultant_user: consultant, action: "hide", section_key: "methodology", published: false)
    result = described_class.call(snapshot: snapshot, report: report)
    expect(result["section_overrides"]).to be_nil
  end

  it "renders hides, edit notes and custom sections through the document template" do
    report.report_section_overrides.create!(consultant_user: consultant, action: "hide", section_key: "methodology")
    report.report_section_overrides.create!(consultant_user: consultant, action: "add", title: "Risk Register",
                                            body: "Demurrage exposure at Jebel Ali.", anchor_section: "recommendations")
    applied = described_class.call(snapshot: snapshot, report: report)
    html = Reports::HtmlBuilder.call(snapshot: applied, report_version: report.version)

    expect(html).to include("Risk Register")
    expect(html).to include("Demurrage exposure at Jebel Ali")
    expect(html).not_to include("How we measured") # methodology section hidden
  end
end
