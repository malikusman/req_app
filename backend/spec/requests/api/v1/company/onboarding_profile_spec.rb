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

  it "saves questionnaire answers and returns completion percent" do
    patch "/api/v1/company/onboarding/questionnaire",
          params: {
            questionnaire_step: 2,
            questionnaire_answers: {
              q01_primary_industry: "Logistics & Transportation",
              q03_employee_count: "51–100",
              q04_headquarters_country: "United Arab Emirates",
              q40_desired_outcomes: ["Faster month-end close"]
            }
          },
          headers: auth_headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["completion_percent"]).to be > 0
    expect(body["questionnaire_step"]).to eq(2)
    company.reload
    expect(company.questionnaire_answers["q01_primary_industry"]).to eq("Logistics & Transportation")
    expect(company.company_profile["industry"]).to eq("logistics")
    expect(company.company_profile["size_band"]).to eq("51-200")
    expect(company.company_profile).not_to have_key("business_goals")
  end

  it "completes portal onboarding without requiring full questionnaire" do
    post "/api/v1/company/onboarding/complete",
         headers: auth_headers_for(user),
         as: :json

    expect(response).to have_http_status(:ok)
    company.reload
    expect(company.portal_onboarding_completed_at).to be_present
    expect(company.engagement_mode).to eq("hybrid")
  end
end
