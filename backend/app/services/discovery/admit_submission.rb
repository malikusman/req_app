module Discovery
  class AdmitSubmission
    class Conflict < StandardError; end

    def self.call(conversation:, employee:, submission_id:, body:, file: nil)
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
        if DiscoveryTurn.where(conversation: conversation).unresolved.exists? ||
            conversation.messages.where(direction: 'inbound', message_type: %w[audio image document], processing_status: %w[pending processing]).exists? ||
            conversation.messages.where(direction: 'inbound').order(:id).last&.raw_payload&.dig('discovery_pending')
          raise Conflict, 'Your previous answer is saved; wait or retry it before sending another answer'
        end
        submission = EmployeeSubmission.create!(conversation: conversation, submission_id: key, body: text)
        DiscoveryRequest.set(admitting: true, submission: submission) do
          if file
            Web::TurnRouter.handle_media(employee: employee, conversation: conversation, file: file, caption: body)
          else
            Web::TurnRouter.handle_text(employee: employee, conversation: conversation, text: text)
          end
        end
        conversation.increment!(:discovery_state_version)
        submission
      end
    end
  end
end
