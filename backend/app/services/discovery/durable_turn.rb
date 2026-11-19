require 'digest'
require 'timeout'

module Discovery
  class DurableTurn
    BUDGET = 85
    MAX_ATTEMPTS = 3
    # Retrieval helpers rescue StandardError for optional context. A deadline
    # must escape those fallbacks so processing actually stops at the boundary.
    class DeadlineExceeded < Exception; end

    def self.digest(conversation)
      Digest::SHA256.hexdigest([conversation.status, conversation.question_count, conversation.state_snapshot].to_json)
    end

    def self.register(conversation, source, text)
      conversation.with_lock do
        saved = source.raw_payload&.dig('discovery_result')
        saved = saved.is_a?(Hash) ? saved.merge('source_message_id' => source.id) : nil
        DiscoveryTurn.find_by(source_message: source) || DiscoveryTurn.create!(
          conversation: conversation, source_message: source, identity: SecureRandom.uuid, user_message: text,
          status: saved ? 'succeeded' : source.raw_payload&.dig('discovery_pending') == false && source.raw_payload&.dig('discovery_error') ? 'failed' : 'queued',
          error_code: source.raw_payload&.dig('discovery_error'),
          result: saved || {})
      end
    end

    def self.waiting(turn, retryable: true)
      { 'assistant_message' => '', 'completed' => false, 'delayed' => true,
        'retryable' => retryable, 'error_code' => turn.error_code }
    end

    def self.call(processor, turn)
      conversation = turn.conversation
      processor.instance_variable_set(:@conversation, conversation)
      source = turn.source_message
      token = SecureRandom.uuid
      claim = conversation.with_lock do
        turn.reload
        if turn.status == 'succeeded'
          next :saved
        end
        next :blocked if turn.status == 'failed'
        if OpenaiCircuitBreaker.open? && turn.status != 'processing'
          turn.update!(status: 'retry_waiting', retry_at: (OpenaiCircuitBreaker.retry_after + 1).seconds.from_now)
          conversation.increment!(:discovery_state_version)
          next :busy
        end
        next :busy if turn.status == 'processing' && turn.lease_until && turn.lease_until > Time.current
        next :busy if turn.status == 'retry_waiting' && turn.retry_at && turn.retry_at > Time.current
        older = DiscoveryTurn.where(conversation: conversation).unresolved.where('source_message_id < ?', source.id).exists?
        next :busy if older
        turn.update!(status: 'processing', lease_token: token, lease_until: 100.seconds.from_now,
          deadline_at: BUDGET.seconds.from_now, attempts: turn.attempts + 1,
          base_revision: conversation.discovery_revision, state_digest: digest(conversation))
        conversation.increment!(:discovery_state_version)
        true
      end
      if claim == :saved
        deliver(turn)
        return turn.result
      end
      return waiting(turn, retryable: claim != :blocked) unless claim == true

      monotonic_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + [turn.deadline_at - Time.current, 0].max
      begin
        result = DiscoveryRequest.set(deadline_at: turn.deadline_at, turn_identity: turn.identity,
                                      base_revision: turn.base_revision) do
          # No database transaction or row lock is held across network processing.
          Timeout.timeout([turn.deadline_at - Time.current, 0.001].max, DeadlineExceeded) do
            processor.execute_turn
          end
        end
      rescue DeadlineExceeded, Timeout::Error, Langgraph::UnavailableError => e
        result = { 'delayed' => true, 'retryable' => true, 'error_code' => 'deadline_exceeded', 'assistant_message' => '' }
      rescue StandardError => e
        Rails.logger.error("[DiscoveryTurn] turn=#{turn.id} exception=#{e.class}")
        result = { 'delayed' => true, 'retryable' => true, 'error_code' => 'processing_failed', 'assistant_message' => '' }
      end

      applied = conversation.with_lock do
        turn.reload
        next false unless turn.lease_token == token && turn.status == 'processing'
        stale = conversation.discovery_revision != turn.base_revision || digest(conversation) != turn.state_digest
        expired = Time.current >= turn.deadline_at || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= monotonic_deadline
        if stale
          result = { 'delayed' => true, 'retryable' => false, 'error_code' => 'stale_turn', 'assistant_message' => '' }
        elsif expired
          result = { 'delayed' => true, 'retryable' => true, 'error_code' => 'deadline_exceeded', 'assistant_message' => '' }
        end
        if result['delayed']
          retryable = result['retryable'] != false && turn.attempts < MAX_ATTEMPTS
          turn.update!(status: retryable ? 'retry_waiting' : 'failed', error_code: result['error_code'] || 'openai_unavailable',
            retry_at: retryable ? [30, OpenaiCircuitBreaker.open? ? OpenaiCircuitBreaker.retry_after : 0].max.seconds.from_now : nil,
            lease_until: nil)
          source.reload.update!(raw_payload: (source.raw_payload || {}).merge('discovery_pending' => retryable, 'discovery_error' => turn.error_code))
        else
          processor.send(:persist_turn!, result, processor.instance_variable_get(:@turn_playbook))
          result['source_message_id'] = source.id
          source.reload.update!(raw_payload: (source.raw_payload || {}).except('discovery_error').merge('discovery_pending' => false, 'discovery_result' => result))
          conversation.increment!(:discovery_revision)
          turn.update!(status: 'succeeded', result: result, lease_until: nil, error_code: nil)
          # Reply row and provider-delivery intent commit atomically with the result.
          deliver(turn)
        end
        conversation.increment!(:discovery_state_version)
        true
      end
      applied ? result : waiting(turn.reload)
    end

    def self.deliver(turn)
      message = DeliverReply.call(conversation: turn.conversation, employee: turn.conversation.employee,
        result: turn.result, channel: turn.source_message.channel == 'web' ? :web : :whatsapp)
      turn.update!(reply_message: message) if message && turn.reply_message_id != message.id
      message
    end
  end
end
