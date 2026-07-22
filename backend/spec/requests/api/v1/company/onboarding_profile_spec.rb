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
            engagement_mode: "documents",
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
end
