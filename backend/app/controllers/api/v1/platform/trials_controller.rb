# frozen_string_literal: true

module Api
  module V1
    module Platform
      class TrialsController < BaseController
        def index
          companies = ::Company.joins(:subscription)
            .includes(:subscription)
            .where(subscriptions: { status: "trial" })
            .where("subscriptions.trial_ends_at <= ?", 7.days.from_now)
            .order("subscriptions.trial_ends_at ASC")

          render json: {
            trials: companies.map do |c|
              {
                company: {
                  id: c.id,
                  name: c.name,
                  report_readiness_score: c.report_readiness_score,
                  completed_count: c.completed_count,
                  invited_count: c.invited_count
                },
                subscription: {
                  trial_ends_at: c.subscription.trial_ends_at,
                  days_remaining: ((c.subscription.trial_ends_at - Time.current) / 1.day).ceil
                }
              }
            end
          }
        end

        def extend
          company = ::Company.find(params[:company_id])
          days = params[:days].to_i.positive? ? params[:days].to_i : 7
          sub = company.subscription
          sub.update!(trial_ends_at: (sub.trial_ends_at || Time.current) + days.days)

          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "trial_extended",
            target: company,
            metadata: { days: days, new_trial_ends_at: sub.trial_ends_at },
            request: request
          )

          render json: {
            company_id: company.id,
            trial_ends_at: sub.trial_ends_at
          }
        end
      end
    end
  end
end
