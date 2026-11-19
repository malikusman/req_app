# frozen_string_literal: true
require 'digest'

module Discovery
  # Explicit, internal repair of a semantically invalid *committed* web result.
  # Never re-admits an answer, replays an LLM or sends a second reply. Ordinary
  # failed turns continue to use the existing saved-answer recovery path.
  class CorrectSavedV2Result
    class Conflict < StandardError; end

    def self.call(turn_id:, result:, expected_revision:, expected_source_sha256:, correction_id:, playbook:)
      turn = DiscoveryTurn.find(turn_id)
      conversation = turn.conversation
      conversation.with_lock do
        turn.reload
        source = turn.source_message.reload
        reply = turn.reply_message
        audit = Array(source.raw_payload['discovery_result_corrections'])
        return reply if audit.any? { |entry| entry['id'] == correction_id }
        raise Conflict, 'Only the latest committed web reply can be corrected' unless
          turn.status == 'succeeded' && source.channel == 'web' && reply&.reply_to_message_id == source.id &&
          conversation.status == 'discovery' && !result['completed'] &&
          conversation.messages.where('id > ?', reply.id).none?
        raise Conflict, 'Conversation changed during correction' unless conversation.discovery_revision == expected_revision
        raise Conflict, 'Saved answer changed during correction' unless Digest::SHA256.hexdigest(source.body) == expected_source_sha256
        raise Conflict, 'Correction must not add a question' unless result['question_count'] == conversation.question_count
        raise Conflict, 'Wrong source result' if result['source_message_id'] && result['source_message_id'] != source.id

        result = result.deep_dup
        result['source_message_id'] = source.id
        V2Contract.prepare!(result, conversation: conversation, source: source)
        result['routing_decision'] = (result['routing_decision'] || {}).merge('reply' => 'saved_result_correction', 'correction_id' => correction_id)
        audit << { 'id' => correction_id, 'reason' => 'employee_discovery_v2_attribution_repair',
          'corrected_at' => Time.current.iso8601, 'previous_revision' => conversation.discovery_revision,
          'source_sha256' => expected_source_sha256, 'previous_result' => turn.result,
          'previous_reply_body' => reply.body }
        processor = ProcessTurnService.new(conversation: conversation, employee: conversation.employee,
          user_message: source.body, inbound_message: source)
        processor.send(:persist_turn!, result, playbook)
        source.update!(raw_payload: source.raw_payload.except('discovery_error').merge(
          'discovery_pending' => false, 'discovery_result' => result, 'discovery_result_corrections' => audit))
        reply.update!(body: result.fetch('assistant_message'), agent_id: result['active_agent_id'],
          routing_decision: result['routing_decision'] || {}, raw_payload: reply.raw_payload.merge('result_correction_id' => correction_id))
        turn.update!(result: result, error_code: nil)
        conversation.increment!(:discovery_revision)
        conversation.increment!(:discovery_state_version)
        reply
      end
    end
  end
end
