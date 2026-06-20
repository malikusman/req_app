# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Platform::Impersonations", type: :request do
  let(:platform_user) { create(:platform_user) }
  let(:headers) { auth_headers_for(platform_user) }
  let(:company) { create(:company, :onboarded) }
  let!(:company_user) do
    create(:company_user, company: company, role: "company_admin", status: "active")
  end

  describe "POST /api/v1/platform/companies/:company_id/impersonate" do
    it "returns a company portal token for the active admin" do
      post "/api/v1/platform/companies/#{company.id}/impersonate", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["token"]).to be_present
      expect(body["expires_at"]).to be_present
      expect(body.dig("company", "id")).to eq(company.id)
      expect(body.dig("user", "email")).to eq(company_user.email)
      expect(ImpersonationSession.where(platform_user: platform_user, company: company)).to exist
    end
  end
end
