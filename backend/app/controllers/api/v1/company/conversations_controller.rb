# frozen_string_literal: true

module Api
  module V1
    module Company
      class ConversationsController < BaseController
        def index
          conversations = policy_scope(::Conversation).includes(:employee).order(updated_at: :desc)
          render json: {
            conversations: conversations.map { |c| conversation_summary(c) }
          }
        end

        def show
          conversation = policy_scope(::Conversation).find(params[:id])
          authorize conversation, :show?
          messages = conversation.messages.discovery_only.order(:created_at)

          render json: {
            conversation: conversation_detail(conversation),
            messages: messages.map { |m| message_json(m) }
          }
        end

        private

        def conversation_summary(conversation)
          employee = conversation.employee
          {
            id: conversation.id,
            employee_id: employee.id,
            employee_name: employee.display_name,
            department: employee.department,
            status: conversation.status,
            question_count: conversation.question_count,
            last_activity_at: conversation.last_activity_at
          }
        end

        def conversation_detail(conversation)
          employee = conversation.employee
          conversation_summary(conversation).merge(
            employee_name: employee.display_name || "Employee ##{employee.id}"
          )
        end

        def message_json(message)
          {
            id: message.id,
            direction: message.direction,
            message_type: message.message_type,
            body: message.body,
            is_discovery_question: message.is_discovery_question,
            created_at: message.created_at
          }
        end
      end
    end
  end
end
