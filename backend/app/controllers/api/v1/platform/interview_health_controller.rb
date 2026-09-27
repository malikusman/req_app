# frozen_string_literal: true

module Api
  module V1
    module Platform
      # GET /api/v1/platform/interview_health?days=30 — see Platform::InterviewHealth.
      class InterviewHealthController < BaseController
        def index
          days = params[:days].to_i.clamp(1, 365)
          days = 30 if params[:days].blank?
          render json: { days: days, companies: ::Platform::InterviewHealth.call(since: days.days.ago) }
        end
      end
    end
  end
end
