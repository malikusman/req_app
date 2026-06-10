# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::Intelligence", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(user) }

  before do
    create(:employee, company: company, participation_status: "completed")
    Intelligence::SnapshotBuilder.call(company: company)
    company.update!(intelligence_snapshot: Intelligence::SnapshotBuilder.call(company: company))
  end

  describe "GET /api/v1/company/intelligence/snapshot" do
    it "returns intelligence snapshot for authenticated company user" do
      get "/api/v1/company/intelligence/snapshot", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("snapshot", "report_readiness_score", "report_readiness_breakdown")
      expect(body["snapshot"]["participation"]).to include("invited", "started", "completed", "completion_rate")
    end

    it "returns unauthorized without token" do
      get "/api/v1/company/intelligence/snapshot"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
