# frozen_string_literal: true

module Api
  module V1
    module Company
      class DiscoveryQuestionsController < BaseController
        def index
          authorize :discovery_question, :index?
          messages = Message.joins(:conversation)
                            .where(conversations: { company_id: current_company.id })
                            .where(direction: "outbound", is_discovery_question: true, consultant_followup: false)
                            .includes(conversation: :employee)
                            .order(created_at: :desc)
                            .limit(100)

          feedbacks = DiscoveryQuestionFeedback.where(company_id: current_company.id, message_id: messages.map(&:id))
                                               .index_by(&:message_id)

          render json: {
            questions: messages.map { |m| question_json(m, feedbacks[m.id]) }
          }
        end

        def feedback
          authorize :discovery_question, :feedback?
          message = Message.joins(:conversation)
                           .where(conversations: { company_id: current_company.id })
                           .find(params[:id])

          record = DiscoveryQuestionFeedback.find_or_initialize_by(
            company: current_company,
            message: message,
            company_user: current_company_user
          )
          record.assign_attributes(feedback: params[:feedback], note: params[:note])
          record.save!

          render json: { feedback: { message_id: message.id, feedback: record.feedback, note: record.note } }
        end

        private

        def question_json(message, feedback)
          employee = message.conversation.employee
          {
            id: message.id,
            body: message.body,
            created_at: message.created_at,
            employee: {
              id: employee.id,
              display_name: employee.display_name,
              department: employee.department
            },
            feedback: feedback&.feedback,
            feedback_note: feedback&.note
          }
        end
      end
    end
  end
end
