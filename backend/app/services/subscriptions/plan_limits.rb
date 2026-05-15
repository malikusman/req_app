# frozen_string_literal: true

module Subscriptions
  class PlanLimits
    LIMITS = {
      "trial" => 25,
      "starter" => 100,
      "growth" => 500,
      "enterprise" => nil
    }.freeze

    def self.conversation_limit_for(plan)
      LIMITS.fetch(plan.to_s, 25)
    end

    def self.apply_defaults!(subscription)
      limit = conversation_limit_for(subscription.plan)
      subscription.update!(conversation_limit: limit) if subscription.conversation_limit.blank?
    end
  end
end
