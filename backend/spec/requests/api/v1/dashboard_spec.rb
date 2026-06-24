# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard APIs", type: :request do
  describe "GET /api/v1/platform/dashboard" do
    let(:platform_user) { create(:platform_user) }

    before do
      stub_request(:get, %r{http://langgraph:8000/health}).to_return(status: 200, body: '{"status":"ok"}')
      stub_request(:get, %r{http://gotenberg:3000/health}).to_return(status: 200, body: "")
    end

    it "returns aggregated platform dashboard payload" do
      create(:company, :onboarded)

      get "/api/v1/platform/dashboard", headers: auth_headers_for(platform_user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["monitoring"]["companies"]["total"]).to be >= 1
      expect(body["system"]["services"]).to include("langgraph", "redis", "openai")
      expect(body["trials_expiring_soon"]).to be_an(Array)
    end
  end

  describe "GET /api/v1/company/dashboard" do
    let(:company) { create(:company, :onboarded) }
    let(:company_user) { create(:company_user, company: company) }

    it "returns company dashboard payload with employees summary" do
      create(:employee, company: company, participation_status: "started", last_active_at: 3.days.ago)

      get "/api/v1/company/dashboard", headers: auth_headers_for(company_user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["snapshot"]).to be_a(Hash)
      expect(body["employees_summary"]["stalled_count"]).to eq(1)
      expect(body["usage"]).to include("conversations_used")
    end
  end

  describe "GET /api/v1/reviewer/dashboard" do
    let(:company) { create(:company, :onboarded) }
    let(:reviewer) { create(:reviewer_user) }

    before do
      create(:reviewer_assignment, company: company, reviewer_user: reviewer)
    end

    it "returns reviewer dashboard payload in one response" do
      get "/api/v1/reviewer/dashboard", headers: auth_headers_for(reviewer)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["companies"].length).to eq(1)
      expect(body["stats"]["assigned_companies"]).to eq(1)
      expect(body).to include("attention_items", "recent_followups", "unread_count")
    end
  end
end
