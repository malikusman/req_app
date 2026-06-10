# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Platform::Intelligence", type: :request do
  let(:platform_user) { create(:platform_user) }
  let(:headers) { auth_headers_for(platform_user) }
  let(:company) { create(:company, :onboarded) }

  before do
    CompanySignal.create!(
      company: company,
      label: "Manual Excel work",
      signal_type: "manual_process",
      strength: 0.8,
      departments: %w[finance],
      evidence_count: 2,
      status: "confirmed",
      first_seen_at: 2.days.ago,
      last_updated_at: 1.day.ago
    )
    Pattern.create!(
      company: company,
      title: "Cross-department approvals",
      description: "Slow sign-offs across teams",
      confidence: 0.75,
      departments: %w[finance operations],
      status: "confirmed",
      first_seen_at: 2.days.ago,
      last_updated_at: 1.day.ago
    )
    Recommendation.create!(
      company: company,
      title: "Automate invoice matching",
      description: "Reduce manual reconciliation",
      status: "published",
      priority: "high",
      company_feedback: "no_response"
    )
    InsightTimelineEvent.create!(
      company: company,
      event_type: "signal_detected",
      title: "Manual process detected",
      summary: "Finance team flagged manual Excel",
      occurred_at: 1.day.ago
    )
  end

  describe "GET /api/v1/platform/companies/:company_id/intelligence/snapshot" do
    it "returns intelligence snapshot for the company" do
      get "/api/v1/platform/companies/#{company.id}/intelligence/snapshot", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("snapshot", "report_readiness_score", "report_readiness_breakdown")
    end
  end

  describe "GET /api/v1/platform/companies/:company_id/intelligence/signals" do
    it "returns company signals" do
      get "/api/v1/platform/companies/#{company.id}/intelligence/signals", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["signals"].length).to eq(1)
    end
  end

  describe "GET /api/v1/platform/companies/:company_id/intelligence/patterns" do
    it "returns company patterns" do
      get "/api/v1/platform/companies/#{company.id}/intelligence/patterns", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["patterns"].length).to eq(1)
    end
  end

  describe "GET /api/v1/platform/companies/:company_id/intelligence/recommendations" do
    it "returns published recommendations" do
      get "/api/v1/platform/companies/#{company.id}/intelligence/recommendations", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["recommendations"].length).to eq(1)
    end
  end

  describe "GET /api/v1/platform/companies/:company_id/intelligence/timeline" do
    it "returns timeline events" do
      get "/api/v1/platform/companies/#{company.id}/intelligence/timeline", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["events"].length).to eq(1)
    end
  end
end
