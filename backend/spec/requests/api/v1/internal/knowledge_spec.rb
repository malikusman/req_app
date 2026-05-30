# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Internal::Knowledge", type: :request do
  let!(:company) { create(:company) }

  describe "GET /api/v1/internal/knowledge/search" do
    it "returns empty results without query" do
      get "/api/v1/internal/knowledge/search",
          params: { company_id: company.id, query: "" },
          headers: internal_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["results"]).to eq([])
    end

    it "returns unauthorized without token" do
      get "/api/v1/internal/knowledge/search", params: { company_id: company.id, query: "workflow" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/internal/companies/:company_id/profile" do
    it "returns profile summary" do
      get "/api/v1/internal/companies/#{company.id}/profile", headers: internal_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["company_id"]).to eq(company.id)
      expect(body).to have_key("profile_text")
    end
  end

  describe "GET /api/v1/internal/companies/:company_id/signals" do
    it "returns signals and patterns" do
      get "/api/v1/internal/companies/#{company.id}/signals", headers: internal_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("signals")
      expect(body).to have_key("patterns")
    end
  end

  describe "GET /api/v1/internal/companies/:company_id/context_bundle" do
    it "returns structured context bundle" do
      company.update!(
        profile_context: {
          "basics" => { "industry" => "technology", "company_size_band" => "51-200",
                        "hq_country" => "US", "one_line_description" => "Test co" },
          "gaps_constraints" => { "known_bottlenecks" => "Manual approvals" }
        }
      )

      get "/api/v1/internal/companies/#{company.id}/context_bundle", headers: internal_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["company_id"]).to eq(company.id)
      expect(body).to have_key("profile_text")
      expect(body).to have_key("profile_completeness")
      expect(body).to have_key("gaps_constraints")
      expect(body).to have_key("info_requests")
      expect(body).to have_key("reviewer_feedback")
      expect(body).to have_key("employee_profile_aggregate")
      expect(body).to have_key("document_inventory")
    end
  end
end
