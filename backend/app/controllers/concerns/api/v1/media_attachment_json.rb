# frozen_string_literal: true

module Api
  module V1
    module MediaAttachmentJson
      extend ActiveSupport::Concern

      private

      def media_attachment_json(attachment, namespace:, company_id: nil)
        Multimodal::MediaAttachmentSerializer.call(
          attachment, request: request, namespace: namespace, company_id: company_id
        )
      end

      def media_attachments_json(conversation, namespace:, company_id: nil)
        conversation.media_attachments.order(:created_at).map do |attachment|
          media_attachment_json(attachment, namespace: namespace, company_id: company_id)
        end
      end
    end
  end
end
