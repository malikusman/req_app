# frozen_string_literal: true

module Multimodal
  module MediaObservability
    module_function

    def record!(event:, attachment:, **extra)
      payload = {
        event: event,
        attachment_id: attachment.id,
        company_id: attachment.company_id,
        conversation_id: attachment.conversation_id,
        attachment_type: attachment.attachment_type,
        status: attachment.status
      }.merge(extra)

      Rails.logger.info("[Multimodal] #{payload.map { |k, v| "#{k}=#{v}" }.join(' ')}")
    end
  end
end
