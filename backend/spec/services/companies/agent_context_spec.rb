# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::AgentContext do
  let(:company) do
    create(:company,
           website_url: "https://example.com",
           company_profile: {
             "industry" => "logistics",
             "size_band" => "51-200",
             "region" => "UAE"
           },
           legacy_profile: { "business_goals" => ["Cut cycle time"] },
           questionnaire_answers: { "q31_operational_challenges" => "Approvals stall" })
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

  it "exposes consultant profile json, with the old goals marked as legacy" do
    json = described_class.consultant_profile_json(company)
    expect(json["company_systems"].first["name"]).to eq("SAP")
    expect(json["website_url"]).to eq("https://example.com")
    expect(json["legacy_profile"]).to eq("business_goals" => ["Cut cycle time"])
    expect(json["questionnaire_summary"]).not_to have_key("business_goals")
  end

  it "gives document analysis the confirmed profile, never the questionnaire answers" do
    snapshot = described_class.docs_profile_snapshot(company)
    expect(snapshot).not_to have_key("questionnaire_answers")
    expect(snapshot.to_json).not_to include("Approvals stall", "Cut cycle time")
  end
end
