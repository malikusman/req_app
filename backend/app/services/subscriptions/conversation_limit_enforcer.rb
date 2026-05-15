# frozen_string_literal: true

module Subscriptions
  class ConversationLimitEnforcer
    def self.can_start_discovery?(company:)
      new(company: company).can_start_discovery?
    end

    def self.record_discovery_started!(company:, conversation:)
      new(company: company).record_discovery_started!(conversation: conversation)
    end

    def initialize(company:)
      @company = company
      @subscription = company.subscription
    end

    def can_start_discovery?
      return true unless @subscription

      limit = effective_limit
      return true if limit.nil?

      @subscription.conversations_used < limit
    end

    def record_discovery_started!(conversation:)
      return unless @subscription
      return if conversation.state_snapshot["counted_toward_limit"]

      @subscription.with_lock do
        @subscription.reload
        conversation.update!(
          state_snapshot: conversation.state_snapshot.merge("counted_toward_limit" => true)
        )
        @subscription.increment!(:conversations_used)
      end
    end

    def limit_reached?
      !can_start_discovery?
    end

    def effective_limit
      @subscription.conversation_limit.presence || PlanLimits.conversation_limit_for(@subscription.plan)
    end

    def usage_summary
      limit = effective_limit
      used = @subscription&.conversations_used.to_i
      {
        conversations_used: used,
        conversation_limit: limit,
        remaining: limit.nil? ? nil : [limit - used, 0].max,
        limit_reached: limit.present? && used >= limit
      }
    end

  end
end
