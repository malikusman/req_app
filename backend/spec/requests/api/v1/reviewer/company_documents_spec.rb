# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reviewer company documents", type: :request do
  let!(:company) { create(:company, :onboarded) }
  let!(:reviewer) { create(:reviewer_user, email: "docs-#{SecureRandom.hex(4)}@example.com") }
  let!(:other_reviewer) { create(:reviewer_user, email: "other-#{SecureRandom.hex(4)}@example.com") }
  let!(:assignment) { create(:reviewer_assignment, company: company, reviewer_user: reviewer) }
  let!(:document) do
    Document.create!(
      company: company,
      source: "company_portal_upload",
      status: "ready",
      storage_key: "documents/#{company.id}/test.pdf",
      filename: "handbook.pdf",
      content_type: "application/pdf",
      byte_size: 12
    )
  end

  before do
    minio = instance_double(Storage::MinioClient, download: "pdf-bytes")
    allow(Storage::MinioClient).to receive(:new).and_return(minio)
  end

  describe "GET /api/v1/reviewer/companies/:company_id/documents" do
    it "lists portal documents for assigned reviewer" do
      get "/api/v1/reviewer/companies/#{company.id}/documents", headers: auth_headers_for(reviewer)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["documents"].map { |d| d["id"] }
      expect(ids).to include(document.id)
    end

    it "forbids unassigned reviewer" do
      get "/api/v1/reviewer/companies/#{company.id}/documents", headers: auth_headers_for(other_reviewer)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/reviewer/companies/:company_id/documents/:id/download" do
    it "downloads file for assigned reviewer" do
      get "/api/v1/reviewer/companies/#{company.id}/documents/#{document.id}/download",
          headers: auth_headers_for(reviewer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("pdf-bytes")
    end

    it "forbids unassigned reviewer" do
      get "/api/v1/reviewer/companies/#{company.id}/documents/#{document.id}/download",
          headers: auth_headers_for(other_reviewer)

      expect(response).to have_http_status(:not_found)
    end
  end
end
