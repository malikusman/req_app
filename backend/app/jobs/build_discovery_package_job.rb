# frozen_string_literal: true

# Builds the consultant handover after an interview completes.
#
# Deliberately swallows failures: the interview is already over and the employee has
# been thanked, so a package that cannot be built should leave a failed row for an
# operator to see rather than retry loudly against a broken model endpoint.
class BuildDiscoveryPackageJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    Discovery::BuildPackageService.call(conversation: conversation)
  rescue StandardError => e
    Rails.logger.error("[BuildDiscoveryPackageJob] conversation=#{conversation_id} #{e.class}: #{e.message}")
  end
end
