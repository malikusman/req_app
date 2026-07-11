# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::HtmlBuilder do
  let(:snapshot) do
    {
      "generated_at" => Time.current.iso8601,
      "company" => { "name" => "Acme Corp", "locale" => "en" },
      "executive_summary" => "12 of 20 employees completed discovery interviews.",
      "readiness" => {
        "score" => 82,
        "breakdown" => { "employees_interviewed" => 75, "departments_represented" => 60 }
      },
      "participation" => { "invited" => 20, "started" => 15, "completed" => 12, "completion_rate" => 0.6 },
      "signals" => [
        { "label" => "Manual re-entry", "strength" => 0.8, "departments" => %w[finance], "evidence_count" => 4,
          "multimodal_evidence" => [] }
      ],
      "patterns" => [{ "title" => "Approval bottlenecks", "description" => "Managers wait on email.", "confidence" => 0.7 }],
      "recommendations" => [
        { "title" => "Automate invoice intake", "description" => "Reduce manual entry.", "priority" => "high",
          "implementation_outline" => "Pilot OCR.", "catalog_matches" => [{ "name" => "DocFlow" }] }
      ],
      "supporting_media" => [
        { "attachment_type" => "image", "summary" => "Screenshot of SAP screen", "employee_department" => "finance" }
      ],
      "delta_from_previous" => { "summary" => "Initial discovery report" }
    }
  end

  it "renders snapshot sections from the ERB template" do
    html = described_class.call(snapshot: snapshot)

    expect(html).to include("Workflow Discovery Report")
    expect(html).to include("Acme Corp")
    expect(html).to include("Readiness breakdown")
    expect(html).to include("Manual re-entry")
    expect(html).to include("Approval bottlenecks")
    expect(html).to include("Automate invoice intake")
    expect(html).to include("high")
    expect(html).to include("Screenshot of SAP screen")
    expect(html).to include("@page")
  end

  it "includes the expert review appendix when notes are provided" do
    html = described_class.call(
      snapshot: snapshot,
      review_notes: [
        { "reviewer" => "Alex Expert", "section_key" => "signals", "body" => "Clarify SAP pain with finance lead." }
      ]
    )

    expect(html).to include("Reviewer notes")
    expect(html).to include("Alex Expert")
    expect(html).to include("Clarify SAP pain with finance lead.")
    expect(html).to include("A4 landscape")
  end

  it "passes report version onto the cover when provided" do
    html = described_class.call(snapshot: snapshot, report_version: 3)

    expect(html).to include("Version 3")
  end
end
