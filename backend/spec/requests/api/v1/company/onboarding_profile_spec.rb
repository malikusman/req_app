# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Company onboarding profile enrichment", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:company_user, company: company) }

  it "saves company_profile and known systems on profile update" do
    patch "/api/v1/company/onboarding/profile",
          params: {
            display_name: "GulfLink Logistics",
            locale: "en",
            company_profile: {
              industry: "logistics",
              size_band: "51-200",
              region: "UAE",
              business_goals: "Reduce AP cycle time",
              annual_revenue_band: "1m_10m"
            },
            known_systems: ["SAP", "Excel"]
          },
          headers: auth_headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
    company.reload
    expect(company.display_name).to eq("GulfLink Logistics")
    expect(company.company_profile["industry"]).to eq("logistics")
    expect(company.company_systems.active.pluck(:name)).to include("SAP", "Excel")
    # Goals and revenue are never onboarding facts (Doc 07 §13), whoever sends them.
    expect(company.company_profile).not_to include("business_goals", "annual_revenue_band")
    expect(company.profile_provenance.dig("industry", "source")).to eq("USER_ENTERED")
  end

  it "keeps the language and display name when a save leaves them out" do
    company.update!(locale: "ar", display_name: "Gulf Link")

    patch "/api/v1/company/onboarding/profile",
          params: { website_url: "https://gulflink.example" },
          headers: auth_headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
    expect(company.reload.locale).to eq("ar")
    expect(company.display_name).to eq("Gulf Link")
  end
end
