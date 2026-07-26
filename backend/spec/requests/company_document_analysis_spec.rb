# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Company document analysis API", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(user) }

  def create_uploaded_doc!
    Document.create!(
      company: company,
      source: "company_portal_upload",
      filename: "policy.txt",
      content_type: "text/plain",
      byte_size: 20,
      storage_key: "documents/#{company.id}/#{SecureRandom.hex(4)}.txt",
      status: "uploaded",
      document_type: "policy",
      sensitivity: "internal",
      reviewer_visible: true
    )
  end

  it "lists analysis run metadata" do
    get "/api/v1/company/document_analysis_runs", headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("runs", "awaiting_analysis_count", "profile_stale", "active_run")
  end

  it "starts an analysis run" do
    create_uploaded_doc!
    allow(DocumentAnalysisRunJob).to receive(:perform_later)

    post "/api/v1/company/document_analysis_runs",
         params: { run_kind: "full" }.to_json,
         headers: headers.merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body).dig("run", "status")).to eq("queued")
  end
end
