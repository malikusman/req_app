# frozen_string_literal: true

module Api
  module V1
    module Company
      class MediaAttachmentsController < BaseController
        include Api::V1::MediaAttachmentDownload

        def index
          attachments = policy_scope(::MediaAttachment)
            .where(status: "ready")
            .includes(:employee, :conversation)
            .order(created_at: :desc)
            .limit(50)

          render json: {
            media_attachments: attachments.map do |attachment|
              Multimodal::MediaAttachmentSerializer.call(
                attachment, request: request, namespace: :company
              ).merge(
                employee_name: attachment.employee.display_name,
                conversation_id: attachment.conversation_id
              )
            end
          }
        end
      end
    end
  end
end
