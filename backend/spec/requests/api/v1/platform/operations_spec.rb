# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Platform operations", type: :request do
  let!(:platform_user) { create(:platform_user) }

  describe "POST /api/v1/platform/companies/:company_id/impersonate" do
    let!(:company) { create(:company, :onboarded) }
    let!(:company_admin) { create(:company_user, company: company, role: "company_admin", status: "active") }

    it "starts impersonation and returns company token payload" do
      post "/api/v1/platform/companies/#{company.id}/impersonate", headers: auth_headers_for(platform_user)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["token"]).to be_present
      expect(body["expires_at"]).to be_present
      expect(body.dig("company", "id")).to eq(company.id)
      expect(body.dig("user", "id")).to eq(company_admin.id)
    end
  end

  describe "GET /api/v1/platform/reviewers" do
    let!(:reviewer_one) { create(:reviewer_user, name: "A Reviewer", email: "a-#{SecureRandom.hex(4)}@example.com") }
    let!(:reviewer_two) { create(:reviewer_user, name: "B Reviewer", email: "b-#{SecureRandom.hex(4)}@example.com") }

    it "returns reviewer rows for platform users" do
      get "/api/v1/platform/reviewers", headers: auth_headers_for(platform_user)

      expect(response).to have_http_status(:ok)
      names = response.parsed_body.fetch("reviewers").map { |r| r.fetch("name") }
      expect(names).to include(reviewer_one.name, reviewer_two.name)
    end
  end

  describe "PATCH /api/v1/platform/reviewers/:id" do
    let!(:reviewer) { create(:reviewer_user, :published_profile, email: "published-#{SecureRandom.hex(4)}@example.com") }

    it "can move a published reviewer back to pending_review" do
      patch "/api/v1/platform/reviewers/#{reviewer.id}",
            params: { platform_verified: false },
            headers: auth_headers_for(platform_user),
            as: :json

      expect(response).to have_http_status(:ok)
      reviewer.reload
      expect(reviewer.platform_verified_at).to be_nil
      expect(reviewer.profile_status).to eq("pending_review")
      expect(response.parsed_body.dig("reviewer", "profile", "headline")).to eq(reviewer.headline)
    end
  end

  describe "GET /api/v1/platform/monitoring" do
    let!(:company) { create(:company, :onboarded) }
    let!(:active_company) { create(:company, :onboarded) }

    before do
      company.subscription.update!(status: "trial", trial_ends_at: 3.days.from_now)
      active_company.subscription.update!(status: "active", plan: "growth")
    end

    it "returns status buckets separately from expiring trials metric" do
      get "/api/v1/platform/monitoring", headers: auth_headers_for(platform_user)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig("subscriptions", "by_status", "trial")).to be >= 1
      expect(body.dig("subscriptions", "by_status", "active")).to be >= 1
      expect(body.dig("subscriptions", "trials_expiring_7d")).to be >= 1
    end
  end
end
