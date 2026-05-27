# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::Me", type: :request do
  describe "GET /api/v1/company/me" do
    let(:company) { create(:company, :onboarded) }
    let(:user) { create(:company_user, company: company) }

    it "returns current user and company when authenticated" do
      get "/api/v1/company/me", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["user"]["id"]).to eq(user.id)
      expect(body["company"]["id"]).to eq(company.id)
      expect(body["impersonating"]).to eq(false)
      expect(body["usage"]).to be_a(Hash)
    end

    it "returns unauthorized without token" do
      get "/api/v1/company/me"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns unauthorized with wrong audience token" do
      platform = create(:platform_user)
      get "/api/v1/company/me", headers: auth_headers_for(platform)

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns forbidden when subscription is inactive" do
      company.subscription.update!(status: "churned")
      get "/api/v1/company/me", headers: auth_headers_for(user)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
