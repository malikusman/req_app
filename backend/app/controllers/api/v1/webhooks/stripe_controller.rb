# frozen_string_literal: true

module Api
  module V1
    module Webhooks
      class StripeController < ApplicationController
        def create
          payload = request.body.read
          event = parse_event(payload)

          return render json: { error: "Invalid payload" }, status: :bad_request unless event

          ::Billing::StripeWebhookHandler.call(event: event)
          render json: { received: true }
        end

        private

        def parse_event(payload)
          secret = ENV["STRIPE_WEBHOOK_SECRET"]
          if secret.blank?
            raise "STRIPE_WEBHOOK_SECRET missing" if Rails.env.production?
            return JSON.parse(payload) if MocksAllowed.allowed?

            return nil
          end

          require "stripe"
          Stripe::Webhook.construct_event(
            payload,
            request.env["HTTP_STRIPE_SIGNATURE"],
            secret
          ).to_hash
        rescue JSON::ParserError, Stripe::SignatureVerificationError => e
          Rails.logger.warn("[Stripe webhook] #{e.message}")
          nil
        end
      end
    end
  end
end
