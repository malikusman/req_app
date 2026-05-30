# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class ConversationsController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          conversations = policy_scope(::Conversation).where(company_id: company.id)
            .includes(:employee)
            .order(updated_at: :desc)
          render json: {
            conversations: conversations.map do |c|
              {
                id: c.id,
                employee_id: c.employee_id,
                employee_name: c.employee.display_name,
                status: c.status,
                question_count: c.question_count,
                last_activity_at: c.last_activity_at
              }
            end
          }
        end

        def show
          conversation = policy_scope(::Conversation).find(params[:id])
          authorize conversation, :show?
          messages = conversation.messages.includes(:media_attachment).order(:created_at)
          render json: {
            conversation: {
              id: conversation.id,
              employee_id: conversation.employee_id,
              status: conversation.status
            },
            messages: messages.map { |m| message_json(m) }
          }
        end

        def reprocess_message
          conversation = policy_scope(::Conversation).find(params[:id])
          authorize conversation, :show?
          message = conversation.messages.includes(:media_attachment).find(params[:message_id])
          attachment = message.media_attachment
          return render json: { error: "No media attachment found" }, status: :unprocessable_entity unless attachment

          attachment.update!(status: "pending", processing_error: nil)
          message.update!(processing_status: "pending")
          ProcessMediaAttachmentJob.perform_later(attachment.id)

          render json: { ok: true, message_id: message.id, attachment_status: attachment.status }
        end

        private

        def message_json(message)
          attachment = message.media_attachment
          {
            id: message.id,
            direction: message.direction,
            message_type: message.message_type,
            body: message.body,
            processing_status: message.processing_status,
            reviewer_followup: message.reviewer_followup,
            is_discovery_question: message.is_discovery_question,
            attachment: attachment && {
              id: attachment.id,
              attachment_type: attachment.attachment_type,
              status: attachment.status,
              processing_error: attachment.processing_error,
              metadata: attachment.metadata
            },
            created_at: message.created_at
          }
        end
      end
    end
  end
end
