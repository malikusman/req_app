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
              business_goals: "Reduce AP cycle time"
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
  end

  it "saves questionnaire answers and returns completion percent" do
    patch "/api/v1/company/onboarding/questionnaire",
          params: {
            questionnaire_step: 2,
            questionnaire_answers: {
              company_industry: "Logistics & Transportation",
              company_size: "51–200",
              company_location: "United Arab Emirates"
            }
          },
          headers: auth_headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["completion_percent"]).to be > 0
    expect(body["questionnaire_step"]).to eq(2)
    company.reload
    expect(company.questionnaire_answers["company_industry"]).to eq("Logistics & Transportation")
    expect(company.company_profile["industry"]).to eq("logistics")
    expect(company.company_profile["size_band"]).to eq("51-200")
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
