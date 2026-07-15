# frozen_string_literal: true

require "rails_helper"

RSpec.describe Intelligence::CatalogMatcher do
  let(:company) { create(:company) }
  let!(:entry) do
    SolutionCatalogEntry.create!(
      name: "Zapier",
      category: "automation",
      tags: ["manual_process"],
      match_keywords: ["manual", "excel"],
      active: true
    )
  end
  let(:signal) do
    create(:company_signal, company: company, label: "Manual excel re-entry", signal_type: "manual_process")
  end

  it "returns matching catalog entries" do
    matches = described_class.call(signal: signal)
    expect(matches.map { |m| m[:name] }).to include("Zapier")
  end
end
