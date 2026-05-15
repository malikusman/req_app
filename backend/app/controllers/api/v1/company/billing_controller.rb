# frozen_string_literal: true

module Api
  module V1
    module Company
      class BillingController < BaseController
        before_action :require_company_admin!, except: [:show]

        def show
          sub = current_company.subscription
          Subscriptions::PlanLimits.apply_defaults!(sub) if sub
          enforcer = Subscriptions::ConversationLimitEnforcer.new(company: current_company)

          render json: {
            subscription: subscription_json(sub),
            usage: enforcer.usage_summary,
            plans: Billing::CheckoutService::PLANS.keys.map { |p| plan_json(p) },
            stripe_configured: ENV["STRIPE_SECRET_KEY"].present?
          }
        end

        def checkout
          plan = params.require(:plan)
          result = Billing::CheckoutService.create_session(company: current_company, plan: plan)
          render json: result
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def require_company_admin!
          render json: { error: "Forbidden" }, status: :forbidden unless current_company_user.company_admin?
        end

        def subscription_json(sub)
          return nil unless sub

          {
            plan: sub.plan,
            status: sub.status,
            trial_ends_at: sub.trial_ends_at,
            current_period_ends_at: sub.current_period_ends_at,
            stripe_customer_id: sub.stripe_customer_id.present?
          }
        end

        def plan_json(plan)
          config = Billing::CheckoutService::PLANS[plan]
          {
            id: plan,
            conversations: config[:conversations],
            amount_cents: config[:amount_cents]
          }
        end
      end
    end
  end
end
