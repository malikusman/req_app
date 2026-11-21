# Compatibility adapter for jobs already persisted before durable turns existed.
class RetryDiscoveryTurnJob < ApplicationJob
  queue_as :default
  BACKOFF = [30.seconds, 2.minutes, 8.minutes].freeze
  MAX_ATTEMPTS = 3

  def perform(conversation_id, user_message, inbound_message_id = nil, attempt = 1)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation
    source = conversation.messages.find_by(id: inbound_message_id)
    return unless source
    if (turn = DiscoveryTurn.find_by(source_message: source))
      ProcessDiscoveryTurnJob.perform_now(turn.id)
      return
    end
    saved = source.raw_payload&.dig('discovery_result')
    return unless conversation.status == 'discovery' || saved.is_a?(Hash)
    return if !saved.is_a?(Hash) && source.raw_payload&.dig('discovery_pending') == false
    if !saved.is_a?(Hash) && OpenaiCircuitBreaker.open?
      self.class.set(wait: OpenaiCircuitBreaker.retry_after.seconds + 1.second).perform_later(conversation_id, user_message, inbound_message_id, attempt)
      return
    end
    result = Discovery::ProcessTurnService.call(conversation: conversation, employee: conversation.employee,
      user_message: source.body.presence || user_message, inbound_message: source, defer_on_failure: false)
    if result['delayed']
      # A modern call creates its durable turn; the sweep now owns recovery.
      return if DiscoveryTurn.exists?(source_message: source)
      if result['retryable'] != false && attempt < MAX_ATTEMPTS
        self.class.set(wait: BACKOFF[attempt - 1]).perform_later(conversation_id, user_message, inbound_message_id, attempt + 1)
      else
        conversation.with_lock do
          source.reload
          source.update!(raw_payload: (source.raw_payload || {}).merge('discovery_pending' => false)) unless source.raw_payload&.dig('discovery_result')
        end
      end
      return
    end
    Discovery::DeliverReply.call(conversation: conversation, employee: conversation.employee,
      result: result, channel: source.channel == 'web' ? :web : :whatsapp)
  end
end
