# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Auth::CompanySessions", type: :request do
  describe "POST /api/v1/auth/company/login" do
    let(:company) { create(:company) }
    let!(:user) { create(:company_user, company: company, email: "admin@test.com", password: "password123") }

    it "returns token and user on valid credentials" do
      post "/api/v1/auth/company/login", params: { email: "admin@test.com", password: "password123" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["token"]).to be_present
      expect(body["user"]["email"]).to eq("admin@test.com")
      expect(body["company"]["id"]).to eq(company.id)
    end

    it "returns unauthorized for invalid password" do
      post "/api/v1/auth/company/login", params: { email: "admin@test.com", password: "wrong" }

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("Invalid email or password")
    end

    it "returns forbidden when subscription is inactive" do
      company.subscription.update!(status: "churned")

      post "/api/v1/auth/company/login", params: { email: "admin@test.com", password: "password123" }

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("Subscription inactive")
    end
  end
end
