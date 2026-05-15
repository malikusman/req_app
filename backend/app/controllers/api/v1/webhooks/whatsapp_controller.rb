# frozen_string_literal: true

module Api
  module V1
    module Webhooks
      class WhatsappController < ApplicationController
        # Meta webhook verification
        def verify
          mode = params["hub.mode"]
          token = params["hub.verify_token"]
          challenge = params["hub.challenge"]

          if mode == "subscribe" && token == ENV["META_VERIFY_TOKEN"]
            render plain: challenge, status: :ok
          else
            render plain: "Forbidden", status: :forbidden
          end
        end

        def create
          raw_body = request.raw_post

          unless Whatsapp::SignatureVerifier.valid?(raw_body, request.headers["X-Hub-Signature-256"])
            return render json: { error: "Invalid signature" }, status: :unauthorized
          end

          payload = JSON.parse(raw_body)
          ProcessWhatsappWebhookJob.perform_later(payload)

          head :ok
        rescue JSON::ParserError
          render json: { error: "Invalid JSON" }, status: :bad_request
        end
      end
    end
  end
end
