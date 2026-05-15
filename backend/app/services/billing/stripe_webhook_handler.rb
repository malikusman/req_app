# frozen_string_literal: true

module Billing
  class StripeWebhookHandler
    def self.call(event:)
      new(event: event).call
    end

    def initialize(event:)
      @event = event
    end

    def call
      case @event["type"]
      when "checkout.session.completed"
        handle_checkout_completed(@event.dig("data", "object"))
      when "customer.subscription.updated", "customer.subscription.created"
        handle_subscription_updated(@event.dig("data", "object"))
      when "customer.subscription.deleted"
        handle_subscription_deleted(@event.dig("data", "object"))
      else
        Rails.logger.info("[Stripe] Ignored event #{@event['type']}")
      end
    end

    private

    def handle_checkout_completed(session)
      company_id = session.dig("metadata", "company_id")
      return unless company_id

      company = Company.find_by(id: company_id)
      return unless company

      sub = company.subscription
      plan = session.dig("metadata", "plan") || "starter"
      sub.update!(
        stripe_customer_id: session["customer"],
        stripe_subscription_id: session["subscription"],
        plan: plan,
        status: "active",
        current_period_ends_at: 1.month.from_now
      )
      Subscriptions::PlanLimits.apply_defaults!(sub)
    end

    def handle_subscription_updated(stripe_sub)
      sub = Subscription.find_by(stripe_subscription_id: stripe_sub["id"])
      return unless sub

      status = map_stripe_status(stripe_sub["status"])
      sub.update!(
        status: status,
        current_period_ends_at: Time.at(stripe_sub["current_period_end"])
      )
    end

    def handle_subscription_deleted(stripe_sub)
      sub = Subscription.find_by(stripe_subscription_id: stripe_sub["id"])
      return unless sub

      sub.update!(status: "churned", stripe_subscription_id: nil)
    end

    def map_stripe_status(stripe_status)
      case stripe_status
      when "active", "trialing" then "active"
      when "past_due", "unpaid" then "suspended"
      else "churned"
      end
    end
  end
end
