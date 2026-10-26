# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::SnapshotBuilder do
  let(:company) { create(:company, name: "Acme Corp", report_readiness_score: 80) }

  it "builds a frozen snapshot hash with core keys" do
    snapshot = described_class.call(company: company, delta: { "summary" => "Initial discovery report" })
    expect(snapshot).to include(
      "company", "readiness", "participation", "signals", "patterns",
      "recommendations", "situation", "implications", "department_coverage"
    )
    expect(snapshot.dig("company", "name")).to eq("Acme Corp")
  end

  describe "ideas and products (Stage 2's)" do
    before { company.agentic_ideas.create!(title: "Invoice Intake Agent", summary: "s", status: "published", source: "generated", confidence: 0.8) }

    it "leaves them out of the snapshot by default" do
      snapshot = described_class.call(company: company, delta: {})
      expect(snapshot["agentic_ideas"]).to eq([])
      expect(snapshot["tools_catalog"]).to eq("curated_matches" => [], "endorsements" => [])
      expect(snapshot.dig("layout", "stage2_previews")).to eq("hidden")
    end

    it "includes them when the company setting shows them" do
      company.update!(settings: company.settings.merge("report_stage2_previews" => "shown"))
      snapshot = described_class.call(company: company, delta: {})
      expect(snapshot["agentic_ideas"].map { |i| i["title"] }).to eq(["Invoice Intake Agent"])
      expect(snapshot.dig("layout", "stage2_previews")).to eq("shown")
    end
  end

  it "leaves the signals and patterns out of the summary once there are findings" do
    company.update!(report_readiness_breakdown: company.report_readiness_breakdown.merge("employees_interviewed" => 1))
    employee = create(:employee, company: company, role_title: "AP Clerk", department: "finance",
                                 participation_status: "completed")
    company.findings.create!(employee: employee, source_key: "k1", area: "invoice entry", department: "finance",
                             role_title: "AP Clerk", friction: "Invoices are re-keyed", status: "approved",
                             frequency_min: 1, frequency_max: 1, frequency_unit: "per_day",
                             duration_min: 30, duration_max: 30, duration_unit: "minutes", effort_type: "active")
    create(:company_signal, company: company, label: "Manual spreadsheet handoffs")

    summary = described_class.call(company: company, delta: {})["executive_summary"]

    expect(summary).to include("1 finding across 1 role")
    expect(summary).not_to include("Manual spreadsheet handoffs")
    expect(summary).not_to include("cross-team")
  end

  it "uses docs-oriented framing when engagement_mode is documents" do
    company.update!(settings: (company.settings || {}).merge("engagement_mode" => "documents"))
    Document.create!(
      company: company,
      filename: "sop.txt",
      content_type: "text/plain",
      status: "ready",
      storage_key: "docs/sop-#{SecureRandom.hex(4)}.txt",
      source: "company_portal_upload",
      byte_size: 40,
      department: "finance"
    )
    create(:company_signal, company: company, label: "Manual spreadsheet handoffs")

    snapshot = described_class.call(company: company, delta: { "summary" => "Initial" })

    expect(snapshot["docs_first_phase"]).to be(true)
    expect(snapshot["report_kind"]).to eq("baseline")
    expect(snapshot["executive_summary"]).to include("Baseline discovery")
    expect(snapshot.dig("situation", "headline")).to include("Document baseline")
  end

  it "includes company profile in the snapshot and executive framing" do
    company.update!(
      company_profile: { "industry" => "logistics", "size_band" => "51-200", "region" => "UAE" },
      settings: (company.settings || {}).merge("engagement_mode" => "documents")
    )
    Document.create!(
      company: company,
      filename: "sop.txt",
      content_type: "text/plain",
      status: "ready",
      storage_key: "docs/sop-#{SecureRandom.hex(4)}.txt",
      source: "company_portal_upload",
      byte_size: 40,
      department: "finance"
    )

    snapshot = described_class.call(company: company, delta: { "summary" => "Initial" })

    expect(snapshot.dig("company", "profile", "industry")).to eq("logistics")
    expect(snapshot["executive_summary"]).to include("logistics")
  end

  it "avoids 'N of 0' interview counts when invited_count drifted" do
    company.update!(
      invited_count: 0,
      report_readiness_breakdown: (company.report_readiness_breakdown || {}).merge("employees_interviewed" => 1),
      settings: (company.settings || {}).merge("engagement_mode" => "hybrid")
    )
    create(:employee, company: company, participation_status: "completed")
    create(:company_signal, company: company, label: "Approval bottlenecks")

    snapshot = described_class.call(company: company, delta: { "summary" => "Initial" })

    expect(snapshot["report_kind"]).to eq("discovery")
    expect(snapshot["executive_summary"]).to include("1 of 1 employees completed discovery")
    expect(snapshot["executive_summary"]).not_to include("of 0")
  end
end
