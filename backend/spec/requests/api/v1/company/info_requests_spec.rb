# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::InfoRequests", type: :request do
  let!(:company) { create(:company, :onboarded) }
  let!(:company_user) { create(:company_user, company: company, role: "company_admin") }
  let!(:reviewer) { create(:reviewer_user, email: "rev-info-#{SecureRandom.hex(4)}@example.com") }
  let(:company_headers) { auth_headers_for(company_user) }
  let(:reviewer_headers) { auth_headers_for(reviewer) }

  before do
    create(:reviewer_assignment, company: company, reviewer_user: reviewer, status: "active")
    allow(Storage::MinioClient).to receive(:new).and_return(instance_double(Storage::MinioClient, upload: true))
  end

  describe "reviewer creates request" do
    it "notifies company and lists for admin" do
      post "/api/v1/reviewer/companies/#{company.id}/profile_info_requests",
           params: {
             subject: "Org chart needed",
             body: "Please upload current operations org chart.",
             profile_section: "documents"
           },
           headers: reviewer_headers,
           as: :json

      expect(response).to have_http_status(:created)
      request_id = response.parsed_body.dig("info_request", "id")
      expect(request_id).to be_present

      get "/api/v1/company/info_requests", headers: company_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["open_count"]).to eq(1)

      post "/api/v1/company/info_requests/#{request_id}/replies",
           params: { body: "Attached our latest org chart." },
           headers: company_headers

      expect(response).to have_http_status(:created)
      expect(CompanyInfoRequest.find(request_id).status).to eq("answered")
    end
  end
end
