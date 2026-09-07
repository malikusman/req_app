# frozen_string_literal: true

require "rails_helper"

# One reviewed snapshot, two renderings. The point of the design is that the
# brief and the full report CANNOT disagree about a number, because neither
# analyses anything -- both project the same snapshot.
RSpec.describe "Report variants" do
  let(:company) { create(:company, name: "Nimbus Trading") }
  let(:report) do
    company.reports.create!(version: 2, status: "ready", visibility: "internal_only",
                            triggered_by_type: "CompanyUser", triggered_by_id: 1,
                            generated_at: Time.current, report_snapshot: snapshot)
  end
  let(:snapshot) do
    {
      "company" => { "name" => "Nimbus Trading", "profile" => {} },
      "report_kind" => "discovery",
      "readiness" => { "score" => 100, "breakdown" => {} },
      "participation" => { "invited" => 6, "started" => 6, "completed" => 5 },
      "evidence_base" => { "interviews" => 5, "documents" => 4, "media" => 2, "departments" => 3 },
      "key_metrics" => [
        { "headline" => "11-14 days", "label" => "AP cycle time", "comparison" => "target 8 days",
          "direction" => "negative", "source" => "Internal document" }
      ],
      "signals" => [
        { "id" => 1, "label" => "Manual re-entry", "strength" => 0.9, "signal_type" => "manual_process",
          "departments" => %w[finance ops], "evidence_count" => 7, "department_count" => 2 },
        { "id" => 2, "label" => "Approval waits", "strength" => 0.5, "signal_type" => "approval_bottleneck",
          "departments" => ["finance"], "evidence_count" => 3, "department_count" => 1 }
      ],
      "patterns" => [{ "id" => 1, "title" => "Handoff friction", "description" => "Work stalls between teams.",
                       "confidence" => 0.8, "departments" => %w[finance ops] }],
      "recommendations" => [
        { "id" => 1, "title" => "Automate invoice intake", "description" => "Remove the re-keying step.",
          "priority" => "high", "impact_score" => 0.95, "feasibility_score" => 0.8, "catalog_matches" => [] }
      ],
      "roadmap" => { "now" => [{ "title" => "Pilot OCR intake", "rationale" => "No new system needed." }],
                     "next" => [], "later" => [] },
      "narrative" => {
        "governing_thought" => "AP cycle time runs 11-14 days against an 8-day target.",
        "supporting_points" => ["Three of four delays start in manual PO reconciliation."],
        "stakes" => "Every quarter of delay compounds the float."
      },
      "executive_summary" => "Nimbus Trading completed five discovery interviews.",
      "delta_from_previous" => { "summary" => "1 new pattern since Report v1" },
      "agentic_ideas" => [], "tools_catalog" => { "curated_matches" => [], "endorsements" => [] },
      "client_stack" => [], "web_research" => [], "implications" => [],
      "situation" => { "headline" => "AP cycle time runs 11-14 days", "context" => "" }
    }
  end

  def html_for(variant)
    Reports::HtmlBuilder.call(snapshot: snapshot, report_version: report.version, variant: variant)
  end

  it "renders the full report in landscape and the brief in portrait" do
    expect(html_for("full")).to include("A4 landscape")
    expect(html_for("exec_brief")).to include("A4 portrait")
  end

  it "quotes the same governing thought and the same metric in both" do
    both = %w[full exec_brief].map { |v| html_for(v) }

    both.each do |html|
      expect(html).to include("11-14 days")
      expect(html).to include("against an 8-day target")
    end
  end

  # The brief's whole job is to be short. If it grows past four pages the section
  # allowlist has stopped doing its job.
  it "keeps the brief to four pages or fewer" do
    pages = html_for("exec_brief").scan(/<section[^>]*class="[^"]*\bpage\b/).size

    expect(pages).to be_between(1, 4)
  end

  it "drops readiness, participation and methodology from the brief but keeps them in the full report" do
    brief = html_for("exec_brief")
    full = html_for("full")

    expect(brief).not_to include("Readiness score, out of 100")
    expect(brief).not_to include("Participation")
    expect(full).to include("Readiness")
    expect(full).to include("Methodology")
  end

  it "rejects an unknown variant rather than silently rendering the full report" do
    expect { Reports::VariantSpec.for("nope") }.to raise_error(ArgumentError, /Unknown report variant/)
  end

  describe "artifacts" do
    before do
      allow(Storage::MinioClient).to receive(:new).and_return(instance_double(Storage::MinioClient, upload: true))
      allow(Reports::PdfGenerator).to receive(:call).and_return("%PDF-1.4")
    end

    it "stores one artifact per variant with its own storage key and page count" do
      Reports::VariantSpec::VARIANTS.each do |variant|
        Reports::ArtifactWriter.call(report: report, variant: variant, html: html_for(variant))
      end

      expect(report.report_artifacts.pluck(:variant)).to match_array(%w[full exec_brief])
      expect(report.artifact_for("exec_brief").storage_key).to include("v2/exec_brief.pdf")
      expect(report.artifact_for("exec_brief").page_count).to be_positive
    end

    # Every existing download path, share link and approval check reads this
    # column. Breaking them to prove a point about normalization is not worth it.
    it "keeps the full report on reports.storage_key for backwards compatibility" do
      Reports::ArtifactWriter.call(report: report, variant: "full", html: html_for("full"))

      expect(report.reload.storage_key).to include("v2/report.pdf")
      expect(report.content_type).to eq("application/pdf")
    end

    it "records the HTML fallback on the artifact when the PDF service is down" do
      html = html_for("exec_brief")
      allow(Reports::PdfGenerator).to receive(:call).and_return(html)

      artifact = Reports::ArtifactWriter.call(report: report, variant: "exec_brief", html: html)

      expect(artifact.content_type).to eq("text/html")
      expect(artifact.error_message).to match(/PDF service unavailable/)
      expect(artifact).not_to be_real_pdf
    end
  end
end
