# frozen_string_literal: true

module Api
  module V1
    module Platform
      class QuestionFeedbackController < BaseController
        def index
          company = ::Company.find(params[:company_id])
          feedbacks = DiscoveryQuestionFeedback.where(company_id: company.id)
                                               .includes(:message, :company_user)
                                               .order(created_at: :desc)

          render json: {
            feedbacks: feedbacks.map do |f|
              {
                id: f.id,
                feedback: f.feedback,
                note: f.note,
                question: f.message.body,
                company_user: f.company_user.name,
                created_at: f.created_at
              }
            end
          }
        end
      end
    end
  end
end
