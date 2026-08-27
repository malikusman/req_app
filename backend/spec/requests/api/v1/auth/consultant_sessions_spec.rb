# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Auth::ConsultantSessions", type: :request do
  describe "POST /api/v1/auth/consultant/login" do
    let!(:user) { create(:consultant_user, email: "rev@test.com", password: "password123") }

    it "returns token and user on valid credentials" do
      post "/api/v1/auth/consultant/login", params: { email: "rev@test.com", password: "password123" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["token"]).to be_present
      expect(body["user"]["email"]).to eq("rev@test.com")
    end

    it "returns unauthorized for invalid credentials" do
      post "/api/v1/auth/consultant/login", params: { email: "rev@test.com", password: "bad" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
