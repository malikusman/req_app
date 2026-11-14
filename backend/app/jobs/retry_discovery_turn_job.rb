# frozen_string_literal: true

class RetryDiscoveryTurnJob < ApplicationJob
  queue_as :default

  BACKOFF = [30.seconds, 2.minutes, 8.minutes].freeze
  MAX_ATTEMPTS = 3

  def perform(conversation_id, user_message, inbound_message_id = nil, attempt = 1)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    employee = conversation.employee
    inbound_message = inbound_message_id && Message.find_by(id: inbound_message_id)
    saved = inbound_message&.raw_payload&.dig("discovery_result")
    return unless conversation.status == "discovery" || saved.is_a?(Hash)
    # Waiting for the shared breaker is not a failed provider attempt. Previously
    # all three retries could expire before its five-minute cooldown elapsed.
    if !saved.is_a?(Hash) && OpenaiCircuitBreaker.open?
      self.class.set(wait: OpenaiCircuitBreaker.retry_after.seconds + 1.second)
        .perform_later(conversation_id, user_message, inbound_message_id, attempt)
      return
    end

    result = Discovery::ProcessTurnService.call(
      conversation: conversation,
      employee: employee,
      user_message: user_message,
      inbound_message: inbound_message,
      defer_on_failure: false
    )

    if result["delayed"] && result["retryable"] != false && attempt < MAX_ATTEMPTS
      wait = BACKOFF[attempt - 1] || 8.minutes
      self.class.set(wait: wait).perform_later(conversation_id, user_message, inbound_message_id, attempt + 1)
      return
    end

    if result["delayed"]
      inbound_message&.update!(raw_payload: (inbound_message.raw_payload || {}).merge("discovery_pending" => false))
      return
    end

    channel = inbound_message&.channel == "web" ? :web : :whatsapp
    Discovery::DeliverReply.call(conversation: conversation, employee: employee, result: result, channel: channel)
  rescue Langgraph::UnavailableError
    return if attempt >= MAX_ATTEMPTS

    wait = BACKOFF[attempt - 1] || 8.minutes
    self.class.set(wait: wait).perform_later(conversation_id, user_message, inbound_message_id, attempt + 1)
  end
end
