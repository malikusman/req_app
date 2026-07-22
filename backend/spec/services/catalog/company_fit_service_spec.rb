# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::CompanyFitService do
  let(:company) do
    create(:company, company_profile: { "industry" => "logistics", "size_band" => "51-200" })
  end
  let!(:signal) { create(:company_signal, company: company, label: "Manual invoice re-entry", strength: 0.9) }

  let!(:entry) do
    SolutionCatalogEntry.create!(
      name: "FreightOps Suite",
      vendor: "Acme",
      category: "saas",
      partnership_tier: "none",
      active: true,
      published_at: Time.current,
      industries: ["logistics"],
      tags: ["invoice"],
      match_keywords: ["invoice", "re-entry"],
      capabilities: ["OCR capture"]
    )
  end

  before do
    allow(Intelligence::CatalogMatcher).to receive(:call).with(signal: signal).and_return(
      [{ solution_id: entry.id, score: 0.5, reason: "keyword overlap" }]
    )
  end

  it "boosts catalog score when company industry matches the entry" do
    matches = described_class.call(company: company)
    record = matches.find { |m| m.solution_catalog_entry_id == entry.id }
    expect(record.score).to be > 0.5
    expect(record.why_it_fits).to include("logistics")
  end
end
