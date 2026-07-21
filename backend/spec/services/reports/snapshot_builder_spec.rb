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
end
