# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Platform::Companies", type: :request do
  describe "GET /api/v1/platform/companies" do
    let(:platform_user) { create(:platform_user) }

    before { create_list(:company, 2) }

    it "lists companies for authenticated platform user" do
      get "/api/v1/platform/companies", headers: auth_headers_for(platform_user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["companies"].length).to be >= 2
    end

    it "returns unauthorized without token" do
      get "/api/v1/platform/companies"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/platform/companies" do
    let(:platform_user) { create(:platform_user) }

    it "creates a company and emails the admin credentials" do
      expect {
        post "/api/v1/platform/companies",
             headers: auth_headers_for(platform_user),
             params: {
               company: { name: "Acme Co" },
               company_admin: { email: "admin@acme.test", name: "Ada Admin", password: "welcome-acme-1" }
             }
      }.to have_enqueued_mail(SignupMailer, :company_admin_credentials)

      expect(response).to have_http_status(:created)
      admin = CompanyUser.find_by(email: "admin@acme.test")
      expect(admin.authenticate("welcome-acme-1")).to eq(admin)
    end
  end

  describe "POST /api/v1/platform/companies/:id/reset_admin_password" do
    let(:platform_user) { create(:platform_user) }
    let(:company) { create(:company, approval_status: "approved", approved_at: 1.day.ago) }
    let!(:admin) { create(:company_user, company: company, status: "active", email: "admin@reset.test", password: "old-password") }

    it "sets a new password and emails it to the company admin" do
      expect {
        post "/api/v1/platform/companies/#{company.id}/reset_admin_password",
             headers: auth_headers_for(platform_user),
             params: { password: "fresh-password-1" }
      }.to have_enqueued_mail(SignupMailer, :company_admin_credentials)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["email"]).to eq("admin@reset.test")
      expect(admin.reload.authenticate("fresh-password-1")).to eq(admin)
    end

    it "returns unprocessable when the company has no admin" do
      admin.destroy!
      post "/api/v1/platform/companies/#{company.id}/reset_admin_password",
           headers: auth_headers_for(platform_user),
           params: { password: "fresh-password-1" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
