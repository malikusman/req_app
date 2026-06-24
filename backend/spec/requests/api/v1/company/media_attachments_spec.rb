# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::MediaAttachments", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:company_user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(company_user) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) { create(:conversation, employee: employee, company: company) }
  let(:message) do
    create(:message, conversation: conversation, direction: "inbound", message_type: "image", body: "SAP screen")
  end
  let!(:attachment) do
    create(:media_attachment,
           message: message,
           company: company,
           employee: employee,
           conversation: conversation,
           attachment_type: "image",
           mime_type: "image/jpeg",
           status: "ready",
           storage_key: "media/#{company.id}/test.jpg",
           caption: "Invoice screen",
           structured_insights: { "summary" => "SAP invoice screen" },
           confidence: 0.9)
  end

  before do
    allow(Storage::MinioClient).to receive(:new).and_return(
      instance_double(Storage::MinioClient, download: "fake-image-bytes")
    )
  end

  describe "GET /api/v1/company/media_attachments" do
    it "lists ready media for the company" do
      get "/api/v1/company/media_attachments", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["media_attachments"].length).to eq(1)
      expect(body["media_attachments"].first["caption"]).to eq("Invoice screen")
      expect(body["media_attachments"].first["download_url"]).to include("/api/v1/company/media_attachments/#{attachment.id}/download")
    end
  end

  describe "GET /api/v1/company/media_attachments/:id/download" do
    it "proxies media from storage" do
      get "/api/v1/company/media_attachments/#{attachment.id}/download", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("fake-image-bytes")
      expect(response.headers["Content-Type"]).to include("image/jpeg")
    end

    it "returns not found when media is not ready" do
      attachment.update!(status: "processing")

      get "/api/v1/company/media_attachments/#{attachment.id}/download", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "backfills dev/simulated storage on missing object and retries download" do
      attachment.update!(storage_key: "dev/simulated/#{attachment.id}", meta_media_id: nil)

      client = instance_double(Storage::MinioClient)
      allow(Storage::MinioClient).to receive(:new).and_return(client)

      attempts = 0
      allow(client).to receive(:download) do
        attempts += 1
        raise Aws::S3::Errors::NoSuchKey.new(nil, "missing") if attempts == 1

        "fake-image-bytes"
      end

      expect(Multimodal::DevStorageBackfill).to receive(:call).with(attachment) do
        attachment.update!(storage_key: "dev/simulated/#{attachment.id}.jpg")
        true
      end

      get "/api/v1/company/media_attachments/#{attachment.id}/download", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("fake-image-bytes")
    end

    it "falls back to dev backfill when meta refetch is unavailable" do
      attachment.update!(
        storage_key: "media/#{company.id}/missing.jpg",
        meta_media_id: "meta-123"
      )
      allow(Whatsapp::MetaClient).to receive(:new).and_return(instance_double(Whatsapp::MetaClient, configured?: false))

      client = instance_double(Storage::MinioClient)
      allow(Storage::MinioClient).to receive(:new).and_return(client)

      attempts = 0
      allow(client).to receive(:download) do
        attempts += 1
        raise Aws::S3::Errors::NoSuchKey.new(nil, "missing") if attempts == 1

        "fake-image-bytes"
      end

      expect(Multimodal::DevStorageBackfill).to receive(:call).with(attachment) do
        attachment.update!(storage_key: "dev/simulated/#{attachment.id}.jpg")
        true
      end

      get "/api/v1/company/media_attachments/#{attachment.id}/download", headers: headers

      expect(response).to have_http_status(:ok)
    end
  end
end
