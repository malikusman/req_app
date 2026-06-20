# frozen_string_literal: true

module Api
  module V1
    module MediaAttachmentIndex
      extend ActiveSupport::Concern

      def index
        attachments = policy_scope(::MediaAttachment)
          .where(status: "ready")
          .includes(:employee, :conversation)
          .order(created_at: :desc)
          .limit(50)

        render json: {
          media_attachments: attachments.map do |attachment|
            Multimodal::MediaAttachmentSerializer.call(
              attachment, request: request, namespace: media_namespace, company_id: params[:company_id]
            ).merge(
              employee_name: attachment.employee.display_name,
              conversation_id: attachment.conversation_id
            )
          end
        }
      end

      private

      def media_namespace
        raise NotImplementedError
      end
    end
  end
end
