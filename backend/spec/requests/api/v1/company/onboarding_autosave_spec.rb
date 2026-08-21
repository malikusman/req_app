# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Company onboarding questionnaire autosave", type: :request do
  let(:company) { create(:company, questionnaire_version: 2) }
  let(:user) { create(:company_user, company: company) }

  it "persists a delta merge onto existing questionnaire_answers" do
    company.update!(questionnaire_answers: { "q01_primary_industry" => "Retail & E-commerce" })

    patch "/api/v1/company/onboarding/questionnaire/answers",
          params: {
            questionnaire_answers: { q02_business_description: "Freight forwarding and warehousing" }
          },
          headers: auth_headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("ok" => true)
    company.reload
    expect(company.questionnaire_answers["q01_primary_industry"]).to eq("Retail & E-commerce")
    expect(company.questionnaire_answers["q02_business_description"]).to eq("Freight forwarding and warehousing")
  end

  it "does not run the heavy update_questionnaire side effects" do
    expect(Companies::QuestionnaireSync).not_to receive(:call)

    all_answers = Companies::QuestionnaireV2Config::FIELD_IDS.to_h { |key| [key, "x"] }
    patch "/api/v1/company/onboarding/questionnaire/answers",
          params: { questionnaire_answers: all_answers },
          headers: auth_headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
    company.reload
    expect(company.questionnaire_completed_at).to be_nil
    expect(company.docs_profile_stale_at).to be_nil
  end

  it "does not change questionnaire_step" do
    company.update!(questionnaire_step: 3)

    patch "/api/v1/company/onboarding/questionnaire/answers",
          params: { questionnaire_answers: { q01_primary_industry: "Healthcare" } },
          headers: auth_headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
    expect(company.reload.questionnaire_step).to eq(3)
  end

  it "returns 404 for a v1 company" do
    v1_company = create(:company, questionnaire_version: 1)
    v1_user = create(:company_user, company: v1_company)

    patch "/api/v1/company/onboarding/questionnaire/answers",
          params: { questionnaire_answers: { company_industry: "Logistics" } },
          headers: auth_headers_for(v1_user),
          as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "contrasts against update_questionnaire, which still runs the heavy side effects" do
    expect(Companies::QuestionnaireSync).to receive(:call).and_call_original

    patch "/api/v1/company/onboarding/questionnaire",
          params: { questionnaire_answers: { q01_primary_industry: "Logistics & Transportation" } },
          headers: auth_headers_for(user),
          as: :json

    expect(response).to have_http_status(:ok)
  end
end
