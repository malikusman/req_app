# frozen_string_literal: true

# Builds role-by-role findings from one interview. Swallows failures for the same
# reason as the discovery package: the employee has done their part, and a finding
# that cannot be built should be logged, not retried loudly.
class BuildFindingsJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    Findings::BuildFromConversation.call(conversation: conversation)
  rescue StandardError => e
    Rails.logger.error("[BuildFindingsJob] conversation=#{conversation_id} #{e.class}: #{e.message}")
  end
end
