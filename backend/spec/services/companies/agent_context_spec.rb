# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::AgentContext do
  let(:company) do
    create(:company,
           website_url: "https://example.com",
           company_profile: {
             "industry" => "logistics",
             "size_band" => "51-200",
             "region" => "UAE",
             "business_goals" => ["Cut cycle time"]
           })
  end

  before do
    company.company_systems.create!(
      name: "SAP",
      normalized_name: "sap",
      category: "erp",
      source: "manual",
      confidence: 1.0,
      active: true
    )
  end

  it "builds agent pack with website and stack" do
    pack = described_class.for_agents(company)
    expect(pack["industry"]).to eq("logistics")
    expect(pack["website_url"]).to eq("https://example.com")
    expect(pack["known_systems"]).to include("SAP")
  end

  it "exposes reviewer profile json" do
    json = described_class.reviewer_profile_json(company)
    expect(json["company_systems"].first["name"]).to eq("SAP")
    expect(json["website_url"]).to eq("https://example.com")
  end
end
