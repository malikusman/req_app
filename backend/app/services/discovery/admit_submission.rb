module Discovery
  class AdmitSubmission
    class Conflict < StandardError; end

    # How a typed-path answer was given. Only these keys and values are kept: a
    # spoken (avatar) answer, and whether it cut the interviewer's question short.
    def self.input_meta(params)
      return {} unless params[:input_mode].to_s == 'voice'

      { 'input_mode' => 'voice', 'interrupted_question' => ActiveModel::Type::Boolean.new.cast(params[:interrupted_question]) == true }
    end

    def self.call(conversation:, employee:, submission_id:, body:, file: nil, input_meta: {})
      text = file ? "attachment:#{Digest::SHA256.file(file.tempfile.path).hexdigest()}:#{body}" : body.to_s.strip
      raise Conflict, 'An answer is required' if text.blank?
      key = submission_id.presence || SecureRandom.uuid # Old clients remain supported.
      raise Conflict, 'Invalid submission identity' unless key.is_a?(String) && key.length <= 100
      conversation.with_lock do
        existing = EmployeeSubmission.find_by(conversation: conversation, submission_id: key)
        if existing
          raise Conflict, 'Submission identity was already used for a different answer' unless existing.body == text
          next existing
        end
        supersede_failed_answer!(conversation) unless file
        if DiscoveryTurn.where(conversation: conversation).unresolved.exists? ||
            conversation.messages.where(direction: 'inbound', message_type: %w[audio image document], processing_status: %w[pending processing]).exists? ||
            conversation.messages.where(direction: 'inbound').order(:id).last&.raw_payload&.dig('discovery_pending')
          raise Conflict, 'Your previous answer is saved; wait or retry it before sending another answer'
        end
        submission = EmployeeSubmission.create!(conversation: conversation, submission_id: key, body: text)
        last_id = conversation.messages.maximum(:id).to_i
        DiscoveryRequest.set(admitting: true, submission: submission) do
          if file
            Web::TurnRouter.handle_media(employee: employee, conversation: conversation, file: file, caption: body)
          else
            Web::TurnRouter.handle_text(employee: employee, conversation: conversation, text: text)
          end
        end
        if input_meta.present? && !file
          conversation.messages.where(direction: 'inbound').where('id > ?', last_id).find_each do |message|
            message.update_columns(raw_payload: (message.raw_payload || {}).merge(input_meta))
          end
        end
        conversation.increment!(:discovery_state_version)
        submission
      end
    end

    # A saved answer the engine could not process (not a transient outage) must not
    # strand the employee: a newly typed answer replaces it. The original message,
    # its error and the failed turn stay on record; nothing is deleted.
    def self.supersede_failed_answer!(conversation)
      return unless Discovery::EmployeeContext.v2?(conversation)
      unresolved = DiscoveryTurn.where(conversation: conversation).unresolved.to_a
      return unless unresolved.size == 1 && unresolved.first.status == 'failed' && rephrasable?(unresolved.first.error_code)
      turn = unresolved.first
      source = turn.source_message
      turn.update!(status: 'superseded')
      source.update!(raw_payload: (source.raw_payload || {}).except('discovery_error').merge(
        'discovery_pending' => false, 'discovery_superseded' => { 'error_code' => turn.error_code, 'at' => Time.current.iso8601 }))
    end

    REPHRASABLE = %w[invalid_discovery_evidence invalid_discovery_capture discovery_clarification_required
                     structured_output_truncated invalid_discovery_v2_contract].freeze

    def self.rephrasable?(code)
      REPHRASABLE.include?(code.to_s)
    end
  end
end
