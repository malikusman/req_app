# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::SnapshotBuilder do
  let(:company) { create(:company, name: "Acme Corp", report_readiness_score: 80) }

  it "builds a frozen snapshot hash with core keys" do
    snapshot = described_class.call(company: company, delta: { "summary" => "Initial discovery report" })
    expect(snapshot).to include("company", "readiness", "participation", "signals", "patterns", "recommendations")
    expect(snapshot.dig("company", "name")).to eq("Acme Corp")
  end
end
