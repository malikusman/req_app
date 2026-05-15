# frozen_string_literal: true

class MarkAbandonedConversationsJob < ApplicationJob
  queue_as :default

  def perform
    Conversation.where(status: %w[onboarding discovery]).find_each do |conversation|
      company = conversation.company
      timeout_hours = company.merged_settings.fetch("discovery_session_timeout_hours", 72).to_i
      next if conversation.last_activity_at.blank?
      next if conversation.last_activity_at > timeout_hours.hours.ago

      conversation.update!(
        status: "abandoned",
        abandoned_at: Time.current,
        abandon_reason: "inactivity_timeout"
      )
    end
  end
end
