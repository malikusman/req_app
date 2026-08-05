# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::Reports", type: :request do
  let(:company) { create(:company) }
  let(:company_user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(company_user) }
  let(:report) do
    create(:report, :ready, company: company,
                            visibility: "shared_with_company",
                            content_type: "application/pdf",
                            storage_key: "reports/#{company.id}/v1/report.pdf")
  end

  before do
    allow(Storage::MinioClient).to receive(:new).and_return(
      instance_double(Storage::MinioClient, download: "%PDF-1.4 fake pdf")
    )
  end

  describe "GET /api/v1/company/reports/:id/download" do
    it "streams the shared report artifact with a .pdf filename" do
      get "/api/v1/company/reports/#{report.id}/download", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to include("%PDF")
      expect(response.headers["Content-Disposition"]).to include("discovery-report-v#{report.version}.pdf")
      expect(response.headers["Content-Disposition"]).to include("attachment")
    end

    it "uses inline disposition when the inline param is present" do
      get "/api/v1/company/reports/#{report.id}/download", params: { inline: "1" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("inline")
    end

    it "returns forbidden when the report is not shared with the company" do
      report.update!(visibility: "internal_only")

      get "/api/v1/company/reports/#{report.id}/download", headers: headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end
