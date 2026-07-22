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
