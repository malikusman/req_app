# frozen_string_literal: true

module Api
  module V1
    module Webhooks
      class StripeController < ApplicationController
        def create
          payload = request.body.read
          event = parse_event(payload)

          return render json: { error: "Invalid payload" }, status: :bad_request unless event

          Billing::StripeWebhookHandler.call(event: event)
          render json: { received: true }
        end

        private

        def parse_event(payload)
          if ENV["STRIPE_WEBHOOK_SECRET"].present?
            require "stripe"
            sig = request.env["HTTP_STRIPE_SIGNATURE"]
            Stripe::Webhook.construct_event(payload, sig, ENV["STRIPE_WEBHOOK_SECRET"]).to_hash
          else
            JSON.parse(payload)
          end
        rescue JSON::ParserError, Stripe::SignatureVerificationError => e
          Rails.logger.warn("[Stripe webhook] #{e.message}")
          nil
        end
      end
    end
  end
end
