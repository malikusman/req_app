# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth signup and passwords", type: :request do
  describe "POST /api/v1/auth/company/signup" do
    it "creates company and user and returns token" do
      post "/api/v1/auth/company/signup",
           params: { company_name: "New Co #{SecureRandom.hex(2)}", name: "Owner", email: "owner-#{SecureRandom.hex(3)}@example.com", password: "password123" },
           as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["token"]).to be_present
      expect(body.dig("user", "role")).to eq("company_admin")
      expect(body.dig("company", "id")).to be_present
    end

    it "sets display_name from company_name" do
      name = "Acme Widgets #{SecureRandom.hex(2)}"
      post "/api/v1/auth/company/signup",
           params: { company_name: name, name: "Owner", email: "owner-#{SecureRandom.hex(3)}@example.com", password: "password123" },
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("company", "display_name")).to eq(name)
      expect(::Company.find(response.parsed_body.dig("company", "id")).display_name).to eq(name)
    end

    it "accepts first and last name fields" do
      post "/api/v1/auth/company/signup",
           params: {
             company_name: "New Co #{SecureRandom.hex(2)}",
             first_name: "Awais",
             last_name: "Athar",
             email: "owner-#{SecureRandom.hex(3)}@example.com",
             password: "password123"
           },
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("user", "name")).to eq("Awais Athar")
    end
  end

  describe "POST /api/v1/auth/reviewer/signup" do
    it "creates reviewer and returns token" do
      post "/api/v1/auth/reviewer/signup",
           params: { name: "Reviewer X", email: "rev-#{SecureRandom.hex(3)}@example.com", password: "password123" },
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["token"]).to be_present
    end

    it "accepts first and last name fields" do
      post "/api/v1/auth/reviewer/signup",
           params: {
             first_name: "Awais",
             last_name: "Athar",
             email: "rev-#{SecureRandom.hex(3)}@example.com",
             password: "password123"
           },
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("user", "name")).to eq("Awais Athar")
    end
  end

  describe "company password reset flow" do
    let!(:company) { create(:company, :onboarded) }
    let!(:user) { create(:company_user, company: company, email: "reset-company@example.com", password: "password123") }

    it "issues and consumes reset token" do
      post "/api/v1/auth/company/forgot_password", params: { email: user.email }, as: :json
      expect(response).to have_http_status(:ok)
      token = user.reload.issue_password_reset_token!

      post "/api/v1/auth/company/reset_password", params: { token: token, password: "newpassword123" }, as: :json
      expect(response).to have_http_status(:ok)

      post "/api/v1/auth/company/login", params: { email: user.email, password: "newpassword123" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "reviewer password reset flow" do
    let!(:reviewer) { create(:reviewer_user, email: "reset-reviewer@example.com", password: "password123") }

    it "issues and consumes reset token" do
      post "/api/v1/auth/reviewer/forgot_password", params: { email: reviewer.email }, as: :json
      expect(response).to have_http_status(:ok)
      token = reviewer.reload.issue_password_reset_token!

      post "/api/v1/auth/reviewer/reset_password", params: { token: token, password: "newpassword123" }, as: :json
      expect(response).to have_http_status(:ok)

      post "/api/v1/auth/reviewer/login", params: { email: reviewer.email, password: "newpassword123" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
