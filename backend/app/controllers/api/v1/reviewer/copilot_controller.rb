# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class CopilotController < BaseController
        before_action :set_company

        def index
          messages = AgentCopilotMessage.where(reviewer_user: current_reviewer_user, company: @company)
                                        .order(:created_at)
                                        .last(50)
          render json: {
            enabled: Companies::AgentFeatures.enabled?(@company, :reviewer_copilot),
            messages: messages.map { |m| copilot_message_json(m) }
          }
        end

        def create
          result = Reviewer::CopilotService.call(
            reviewer: current_reviewer_user,
            company: @company,
            user_message: params.require(:message)
          )
          render json: {
            message: copilot_message_json(result[:message]),
            citations: result[:citations]
          }
        rescue Langgraph::UnavailableError => e
          render json: { error: e.message }, status: :service_unavailable
        end

        private

        def set_company
          @company = Company.find(params[:company_id])
          authorize @company, :show?
        end

        def copilot_message_json(message)
          {
            id: message.id,
            role: message.role,
            body: message.body,
            citations: message.citations,
            created_at: message.created_at
          }
        end
      end
    end
  end
end
