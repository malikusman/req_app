# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Reviewer::Reports", type: :request do
  let(:company) { create(:company) }
  let(:reviewer) { create(:reviewer_user) }
  let(:headers) { auth_headers_for(reviewer) }
  let(:report) do
    create(:report, :ready, company: company,
                            content_type: "application/pdf",
                            storage_key: "reports/#{company.id}/v1/report.pdf")
  end

  before do
    create(:reviewer_assignment, company: company, reviewer_user: reviewer)
    allow(Storage::MinioClient).to receive(:new).and_return(
      instance_double(Storage::MinioClient, download: "%PDF-1.4 fake pdf")
    )
  end

  describe "GET /api/v1/reviewer/companies/:company_id/reports/:id/download" do
    it "streams the ready report artifact with a .pdf filename" do
      get "/api/v1/reviewer/companies/#{company.id}/reports/#{report.id}/download", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to include("%PDF")
      expect(response.headers["Content-Disposition"]).to include("discovery-report-v#{report.version}.pdf")
    end

    it "uses inline disposition when the inline param is present" do
      get "/api/v1/reviewer/companies/#{company.id}/reports/#{report.id}/download",
          params: { inline: "1" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("inline")
    end
  end

  describe "GET /api/v1/reviewer/companies/:company_id/reports/:id/preview" do
    it "renders the live HTML preview" do
      allow(Reports::RegenerateWithReviewService).to receive(:render_html).and_return("<html><body>preview</body></html>")

      get "/api/v1/reviewer/companies/#{company.id}/reports/#{report.id}/preview", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("<html>")
    end

    it "returns unprocessable when the report snapshot is missing" do
      report.update!(report_snapshot: {})

      get "/api/v1/reviewer/companies/#{company.id}/reports/#{report.id}/preview", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
