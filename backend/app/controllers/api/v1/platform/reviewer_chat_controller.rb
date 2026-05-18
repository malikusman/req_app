# frozen_string_literal: true

module Api
  module V1
    module Platform
      class ReviewerChatController < BaseController
        def index
          company = ::Company.find(params[:company_id])
          messages = ReviewerChatMessage.where(company_id: company.id)
            .order(:created_at)
            .includes(:sender_reviewer_user)

          render json: {
            messages: messages.map { |m|
              {
                id: m.id,
                body: m.body,
                sender_name: m.sender_reviewer_user.name,
                created_at: m.created_at
              }
            }
          }
        end
      end
    end
  end
end
