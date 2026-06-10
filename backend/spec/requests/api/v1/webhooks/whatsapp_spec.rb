# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Webhooks::Whatsapp", type: :request do
  describe "GET /api/v1/webhooks/whatsapp" do
    around do |example|
      previous = ENV["META_VERIFY_TOKEN"]
      ENV["META_VERIFY_TOKEN"] = "verify-token"
      example.run
    ensure
      ENV["META_VERIFY_TOKEN"] = previous
    end

    it "returns challenge when verify token matches" do
      get "/api/v1/webhooks/whatsapp",
          params: { "hub.mode" => "subscribe", "hub.verify_token" => "verify-token", "hub.challenge" => "12345" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("12345")
    end

    it "returns forbidden when verify token is wrong" do
      get "/api/v1/webhooks/whatsapp",
          params: { "hub.mode" => "subscribe", "hub.verify_token" => "wrong", "hub.challenge" => "12345" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/webhooks/whatsapp" do
    let(:payload) { { entry: [] }.to_json }

    around do |example|
      previous = ENV["META_APP_SECRET"]
      ENV["META_APP_SECRET"] = "test-secret"
      example.run
    ensure
      ENV["META_APP_SECRET"] = previous
    end

    it "enqueues webhook processing when signature is valid" do
      signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", "test-secret", payload)

      expect {
        post "/api/v1/webhooks/whatsapp",
             params: payload,
             headers: { "CONTENT_TYPE" => "application/json", "X-Hub-Signature-256" => signature }
      }.to have_enqueued_job(ProcessWhatsappWebhookJob)

      expect(response).to have_http_status(:ok)
    end

    it "returns unauthorized when signature is invalid" do
      post "/api/v1/webhooks/whatsapp",
           params: payload,
           headers: { "CONTENT_TYPE" => "application/json", "X-Hub-Signature-256" => "sha256=invalid" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
