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

  it "returns questionnaire_version 1 on show for a default company" do
    get "/api/v1/company/onboarding",
        headers: auth_headers_for(user),
        as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["questionnaire_version"]).to eq(1)
    expect(body["step"]).to eq(1)
  end

  context "when the company questionnaire_version is 2" do
    let(:company) { create(:company, questionnaire_version: 2) }

    it "whitelists v2 keys and rejects v1 keys" do
      patch "/api/v1/company/onboarding/questionnaire",
            params: {
              questionnaire_step: 4,
              questionnaire_answers: {
                q01_primary_industry: "Logistics & Transportation",
                q02_business_description: "Freight forwarding and warehousing",
                company_industry: "Logistics"
              }
            },
            headers: auth_headers_for(user),
            as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body).with_indifferent_access
      expect(body[:questionnaire_answers]).to include("q01_primary_industry", "q02_business_description")
      company.reload
      expect(company.questionnaire_answers["q01_primary_industry"]).to eq("Logistics & Transportation")
      expect(company.questionnaire_answers["q02_business_description"]).to eq("Freight forwarding and warehousing")
      expect(company.questionnaire_answers).not_to have_key("company_industry")
    end

    it "clamps questionnaire_step to the v2 range (1..8)" do
      patch "/api/v1/company/onboarding/questionnaire",
            params: {
              questionnaire_step: 20,
              questionnaire_answers: { q01_primary_industry: "Retail & E-commerce" }
            },
            headers: auth_headers_for(user),
            as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["questionnaire_step"]).to eq(8)
    end

    it "reports a step clamped within the v2 range on show" do
      company.update!(questionnaire_step: 12)

      get "/api/v1/company/onboarding",
          headers: auth_headers_for(user),
          as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["step"]).to eq(8)
      expect(body["questionnaire_version"]).to eq(2)
    end

    it "reports a non-zero completion percent for saved v2 answers, agreeing with show" do
      patch "/api/v1/company/onboarding/questionnaire",
            params: {
              questionnaire_answers: {
                q01_primary_industry: "Logistics & Transportation",
                q02_business_description: "Freight forwarding and warehousing",
                q03_employee_count: "51–100"
              }
            },
            headers: auth_headers_for(user),
            as: :json

      expect(response).to have_http_status(:ok)
      patch_body = JSON.parse(response.body)
      expect(patch_body["section_status"].keys).to eq((1..8).map(&:to_s))
      expect(patch_body["completion_percent"]).to eq(
        ((3.0 / Companies::QuestionnaireV2Config::FIELD_IDS.size) * 100).round
      )

      get "/api/v1/company/onboarding", headers: auth_headers_for(user), as: :json
      body = JSON.parse(response.body)
      expect(body["completion_percent"]).to eq(patch_body["completion_percent"])
    end

    it "stamps questionnaire_completed_at when every v2 field is answered" do
      all_answers = Companies::QuestionnaireV2Config::FIELD_IDS.to_h { |key| [key, "x"] }

      patch "/api/v1/company/onboarding/questionnaire",
            params: { questionnaire_answers: all_answers },
            headers: auth_headers_for(user),
            as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["completion_percent"]).to eq(100)
      expect(body["questionnaire_completed_at"]).to be_present
      company.reload
      expect(company.questionnaire_completed_at).to be_present
    end
  end
end
