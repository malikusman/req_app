# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class ConversationsController < BaseController
        include Api::V1::MediaAttachmentJson
        include Api::V1::DiscoveryConversationJson

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
          employee = conversation.employee
          messages = conversation.messages.includes(:media_attachment).order(:created_at)

          render json: {
            conversation: {
              id: conversation.id,
              employee_id: conversation.employee_id,
              status: conversation.status,
              discovery_state: discovery_state_json(conversation, employee)
            },
            discovery_provenance: discovery_provenance_json(messages),
            messages: messages.map { |m| message_json(m) },
            media_attachments: media_attachments_json(
              conversation, namespace: :consultant, company_id: conversation.company_id
            )
          }
        end

        private

        def message_json(message)
          json = {
            id: message.id,
            direction: message.direction,
            message_type: message.message_type,
            body: message.body,
            consultant_followup: message.consultant_followup,
            is_discovery_question: message.is_discovery_question,
            created_at: message.created_at
          }.merge(message_provenance_fields(message))
          if message.media_attachment
            json[:media_attachment] = media_attachment_json(
              message.media_attachment,
              namespace: :consultant,
              company_id: params[:company_id]
            )
          end
          json
        end
      end
    end
  end
end
