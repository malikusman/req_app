# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public report share links", type: :request do
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  let(:company) { create(:company) }
  let(:report) do
    create(:report, :ready, company: company,
                            visibility: "shared_with_company",
                            content_type: "application/pdf",
                            storage_key: "reports/#{company.id}/v1/report.pdf",
                            share_token: "test-share-token",
                            share_token_expires_at: 1.day.from_now)
  end
  let(:token) { report.share_token }

  before do
    client = instance_double(Storage::MinioClient, download: "%PDF-1.4 fake pdf")
    allow(Storage::MinioClient).to receive(:new).and_return(client)
  end

  def get_share_link
    get "/api/v1/public/reports/#{token}"
  end

  it "streams the stored PDF artifact with a .pdf filename" do
    get_share_link

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.body).to include("%PDF")
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    expect(response.headers["Content-Disposition"]).to include("discovery-report-v#{report.version}.pdf")
  end

  it "streams an HTML fallback artifact with a .html filename" do
    report.update!(content_type: "text/html", storage_key: "reports/#{company.id}/v#{report.version}/report.html")
    client = instance_double(Storage::MinioClient, download: "<html><body>fallback</body></html>")
    allow(Storage::MinioClient).to receive(:new).and_return(client)

    get_share_link

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("<html>")
    expect(response.headers["Content-Disposition"]).to include("discovery-report-v#{report.version}.html")
  end

  it "returns not found when the share token has expired" do
    report.update!(share_token_expires_at: 1.day.ago)

    get_share_link

    expect(response).to have_http_status(:not_found)
  end

  it "returns too_many_requests when the rate limit is exceeded" do
    limit = Api::V1::Public::ReportsController::MAX_PER_WINDOW

    (limit + 1).times { get_share_link }

    expect(response).to have_http_status(:too_many_requests)
    expect(JSON.parse(response.body)).to eq("error" => "Too many requests. Please try again later.")
  end
end
