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
          messages = conversation.messages.order(:created_at)
          render json: {
            conversation: {
              id: conversation.id,
              employee_id: conversation.employee_id,
              status: conversation.status
            },
            messages: messages.map { |m| message_json(m) }
          }
        end

        private

        def message_json(message)
          {
            id: message.id,
            direction: message.direction,
            message_type: message.message_type,
            body: message.body,
            reviewer_followup: message.reviewer_followup,
            is_discovery_question: message.is_discovery_question,
            created_at: message.created_at
          }
        end
      end
    end
  end
end
