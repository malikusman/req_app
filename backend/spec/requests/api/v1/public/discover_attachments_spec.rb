# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Public::DiscoverAttachments", type: :request do
  let(:company) do
    create(:company, settings: Company::DEFAULT_SETTINGS.merge("discovery_multimodal_enabled" => true))
  end
  let(:employee) do
    create(:employee, company: company, onboarding_step: "verified", participation_status: "started")
  end
  let!(:session) do
    create(:employee_web_session, employee: employee, company: company, verified_at: Time.current)
  end
  let(:headers) { employee_web_headers(session: session, employee: employee) }
  let!(:conversation) do
    create(:conversation, employee: employee, company: company, status: "discovery", question_count: 1)
  end

  let(:jpeg_upload) do
    file = Tempfile.new(["discover", ".jpg"])
    file.binmode
    file.write(Multimodal::DevStorageBackfill::MINIMAL_JPEG)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/jpeg", original_filename: "screenshot.jpg")
  end

  before do
    allow(Storage::MinioClient).to receive(:new).and_return(instance_double(Storage::MinioClient, upload: true))
    allow(ProcessMediaAttachmentJob).to receive(:perform_later)
  end

  describe "POST /api/v1/public/discover/attachments" do
    it "accepts image uploads during discovery and returns ack message" do
      post "/api/v1/public/discover/attachments",
           params: { file: jpeg_upload, caption: "My workflow screen" },
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["messages"]).to be_present
      ack = body["messages"].reverse.find { |m| m["direction"] == "outbound" }
      expect(ack["body"]).to include("image")
      expect(ack["body"]).to include("processing")
      expect(MediaAttachment.count).to eq(1)
      expect(MediaAttachment.last.message.channel).to eq("web")
      expect(ProcessMediaAttachmentJob).to have_received(:perform_later)
    end

    it "rejects uploads during profiling" do
      conversation.update!(status: "profiling")

      post "/api/v1/public/discover/attachments", params: { file: jpeg_upload }, headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      notice = body["messages"].reverse.find { |m| m["direction"] == "outbound" }
      expect(notice["body"]).to include("text message")
      expect(MediaAttachment.count).to eq(0)
    end

    it "rejects uploads during onboarding" do
      conversation.update!(status: "onboarding")
      employee.update!(onboarding_step: "awaiting_consent")

      post "/api/v1/public/discover/attachments", params: { file: jpeg_upload }, headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      notice = body["messages"].reverse.find { |m| m["direction"] == "outbound" }
      expect(notice["body"]).to include("onboarding")
      expect(MediaAttachment.count).to eq(0)
    end

    it "rejects uploads when multimodal is disabled" do
      company.update!(settings: company.settings.merge("discovery_multimodal_enabled" => false))

      post "/api/v1/public/discover/attachments", params: { file: jpeg_upload }, headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      notice = body["messages"].reverse.find { |m| m["direction"] == "outbound" }
      expect(notice["body"]).to include("text messages")
      expect(MediaAttachment.count).to eq(0)
    end

    it "returns unprocessable entity for unsupported file types" do
      txt = Tempfile.new(["notes", ".txt"])
      txt.write("hello")
      txt.rewind
      upload = Rack::Test::UploadedFile.new(txt.path, "text/plain", original_filename: "notes.txt")

      post "/api/v1/public/discover/attachments", params: { file: upload }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("Unsupported")
    end
  end
end
