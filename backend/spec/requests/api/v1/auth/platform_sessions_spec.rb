# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Auth::PlatformSessions", type: :request do
  describe "POST /api/v1/auth/platform/login" do
    let!(:user) { create(:platform_user, email: "admin@platform.test", password: "password123") }

    it "returns token and user on valid credentials" do
      post "/api/v1/auth/platform/login", params: { email: "admin@platform.test", password: "password123" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["token"]).to be_present
      expect(body["user"]["email"]).to eq("admin@platform.test")
    end

    it "returns unauthorized for invalid credentials" do
      post "/api/v1/auth/platform/login", params: { email: "admin@platform.test", password: "nope" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
