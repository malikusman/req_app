# frozen_string_literal: true

class RetryDiscoveryTurnJob < ApplicationJob
  queue_as :default

  BACKOFF = [30.seconds, 2.minutes, 8.minutes].freeze
  MAX_ATTEMPTS = 3

  def perform(conversation_id, user_message, inbound_message_id = nil, attempt = 1)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation&.status == "discovery"

    employee = conversation.employee
    inbound_message = inbound_message_id && Message.find_by(id: inbound_message_id)

    result = Discovery::ProcessTurnService.call(
      conversation: conversation,
      employee: employee,
      user_message: user_message,
      inbound_message: inbound_message,
      defer_on_failure: false
    )

    if result["delayed"] && attempt < MAX_ATTEMPTS
      wait = BACKOFF[attempt - 1] || 8.minutes
      self.class.set(wait: wait).perform_later(conversation_id, user_message, inbound_message_id, attempt + 1)
      return
    end

    return if result["delayed"]

    Whatsapp::DiscoveryHandler.new(employee: employee, conversation: conversation).deliver_assistant_reply(result)
  rescue Langgraph::UnavailableError
    return if attempt >= MAX_ATTEMPTS

    wait = BACKOFF[attempt - 1] || 8.minutes
    self.class.set(wait: wait).perform_later(conversation_id, user_message, inbound_message_id, attempt + 1)
  end
end
