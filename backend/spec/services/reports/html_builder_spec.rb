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
      "evidence_base" => { "interviews" => 4, "documents" => 3, "media" => 1, "departments" => 2 },
      "delta_from_previous" => { "summary" => "Initial discovery report" }
    }
  end

  it "renders snapshot sections from the ERB template" do
    html = described_class.call(snapshot: snapshot)

    expect(html).to include("Discovery Report")
    expect(html).to include("Acme Corp")
    expect(html).to include("Readiness breakdown")
    expect(html).to include("Manual re-entry")
    expect(html).to include("Approval bottlenecks")
    expect(html).to include("Automate invoice intake")
    expect(html).to include("high")
    expect(html).to include("@page")
    # The evidence base is stated as method, not reproduced as content.
    expect(html).to include("3 internal documents")
  end

  it "reproduces no interview excerpt, media caption or document filename" do
    with_evidence = snapshot.deep_dup
    with_evidence["signals"].first["source_excerpts"] = [
      { "excerpt" => "I literally re-key every line by hand, it takes me all Friday" }
    ]

    html = described_class.call(snapshot: with_evidence)

    # Even when a stale snapshot still carries excerpts, the deliverable must not
    # render them: an employee spoke candidly to an interviewer, and quoting them
    # back to their employer is a confidentiality problem, not a design choice.
    expect(html).not_to include("re-key every line by hand")
  end

  it "renders the executive brief variant as four portrait pages" do
    html = described_class.call(snapshot: snapshot, variant: Reports::VariantSpec::EXEC_BRIEF)

    expect(html).to include("A4 portrait")
    expect(html).to include("Executive brief")
    expect(html.scan(/<section[^>]*class="[^"]*\bpage\b/).size).to be <= 4
  end

  it "includes the expert review appendix when notes are provided" do
    html = described_class.call(
      snapshot: snapshot,
      review_notes: [
        { "consultant" => "Alex Expert", "section_key" => "signals", "body" => "Clarify SAP pain with finance lead." }
      ]
    )

    expect(html).to include("Expert judgement").or include("Consultant notes")
    expect(html).to include("Alex Expert")
    expect(html).to include("Clarify SAP pain with finance lead.")
    expect(html).to include("A4 landscape")
  end

  it "renders structured findings with disposition and evidence refs in the appendix" do
    html = described_class.call(
      snapshot: snapshot.merge(
        "tools_catalog" => {
          "curated_matches" => [
            {
              "name" => "DocFlow",
              "category" => "Document AI",
              "vendor" => "Acme",
              "reason" => "Fits invoice intake",
              "solution_id" => 1,
              "endorsements" => [
                { "disposition" => "endorse", "consultant_name" => "Alex Expert", "rationale" => "Strong fit" }
              ]
            }
          ],
          "endorsements" => [],
          "disclaimer" => "Catalog matches are illustrative."
        }
      ),
      review_notes: [],
      review_overlay: {
        "notes" => [],
        "section_dispositions" => [],
        "structured_findings" => [
          {
            "consultant" => "Alex Expert",
            "kind" => "executive_conclusion",
            "title" => "Executive conclusion",
            "disposition" => "endorse",
            "severity" => "material",
            "body" => "Readiness score is well supported.",
            "evidence_refs" => %w[signal:1 pattern:2]
          }
        ]
      }
    )

    expect(html).to include("Structured findings")
    expect(html).to include("Readiness score is well supported.")
    expect(html).to include("Endorse")
    expect(html).to include("signal:1")
    expect(html).to include("pattern:2")
    expect(html).to include("DocFlow")
    expect(html).to include("endorsement-chip")
  end

  it "passes report version onto the cover when provided" do
    html = described_class.call(snapshot: snapshot, report_version: 3)

    expect(html).to include("Version 3")
  end
end
