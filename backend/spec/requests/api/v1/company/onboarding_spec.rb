# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::Onboarding", type: :request do
  let!(:company) { create(:company, display_name: "Acme Corp") }
  let!(:user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(user) }

  before do
    company.subscription.update!(status: "churned")
  end

  def complete_required_sections!
    patch "/api/v1/company/onboarding/profile",
          params: {
            section: "basics",
            data: {
              industry: "technology",
              company_size_band: "51-200",
              hq_country: "US",
              one_line_description: "Software company"
            }
          },
          headers: headers, as: :json
    patch "/api/v1/company/onboarding/profile",
          params: {
            section: "strategy",
            data: {
              top_priorities: %w[growth],
              transformation_goals: "Modernize ops",
              digital_vision_maturity: "developing",
              success_metrics: "ROI"
            }
          },
          headers: headers, as: :json
    patch "/api/v1/company/onboarding/profile",
          params: {
            section: "operations",
            data: {
              primary_departments: %w[Ops],
              key_workflows: "Order to cash",
              systems_tools: %w[ERP],
              automation_level: "developing",
              operational_pain_points: "Manual handoffs"
            }
          },
          headers: headers, as: :json
    patch "/api/v1/company/onboarding/profile",
          params: {
            section: "technology_data",
            data: {
              it_maturity: "developing",
              integration_level: "Partial",
              data_governance: "Informal",
              security_posture: "moderate"
            }
          },
          headers: headers, as: :json
    patch "/api/v1/company/onboarding/profile",
          params: {
            section: "people_culture",
            data: {
              org_structure_notes: "Functional",
              change_readiness: "moderate",
              digital_literacy: "moderate",
              collaboration_tools: "Slack"
            }
          },
          headers: headers, as: :json
  end

  it "allows onboarding show even when subscription is inactive" do
    get "/api/v1/company/onboarding", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["step"]).to eq(1)
    expect(response.parsed_body["completeness"]).to be_present
  end

  it "saves profile sections and advances step" do
    patch "/api/v1/company/onboarding/profile",
          params: {
            section: "basics",
            data: {
              industry: "technology",
              company_size_band: "51-200",
              hq_country: "US",
              one_line_description: "Software company"
            }
          },
          headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["step"]).to eq(2)
    expect(company.reload.profile_context.dig("basics", "industry")).to eq("technology")
  end

  it "blocks completing onboarding until required sections are done" do
    post "/api/v1/company/onboarding/complete", headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["missing_required_sections"]).to be_present
  end

  it "allows completing onboarding after required sections without employees" do
    complete_required_sections!
    post "/api/v1/company/onboarding/complete", headers: headers

    expect(response).to have_http_status(:ok)
    expect(company.reload.portal_onboarding_completed_at).to be_present
    expect(user.reload.onboarding_completed_at).to be_present
  end
end
