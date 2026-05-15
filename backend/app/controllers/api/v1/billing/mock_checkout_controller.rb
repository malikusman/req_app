# frozen_string_literal: true

module Api
  module V1
    module Billing
      class MockCheckoutController < ApplicationController
        def show
          payload = Rails.cache.read("mock_checkout:#{params[:token]}")&.with_indifferent_access
          return render plain: "Invalid or expired checkout link", status: :not_found unless payload

          company = Company.find(payload[:company_id])
          sub = company.subscription
          plan = payload[:plan].to_s

          Subscriptions::PlanLimits.apply_defaults!(sub)
          sub.update!(
            plan: plan,
            status: "active",
            current_period_ends_at: 1.month.from_now,
            conversation_limit: Subscriptions::PlanLimits.conversation_limit_for(plan)
          )

          Rails.cache.delete("mock_checkout:#{params[:token]}")
          redirect_to "#{ENV.fetch('APP_HOST', 'http://localhost:5173')}/company/billing?success=1&mock=1", allow_other_host: true
        end
      end
    end
  end
end
