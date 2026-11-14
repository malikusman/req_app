# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class TaskSelectionReviewsController < BaseController
        def show
          render json: review.read(params[:version])
        end

        def command
          revision = review.apply(request.request_parameters, actor: current_consultant_user)
          render json: review.read(revision.version)
        rescue TaskSelection::Review::Invalid => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue TaskSelection::Review::Conflict => e
          render json: { error: e.message }, status: :conflict
        end

        private

        def review
          @review ||= begin
            company = policy_scope(::Company).find(params[:company_id])
            run = policy_scope(::TaskIntelligenceRun).where(company: company).find(params[:task_intelligence_run_id])
            TaskSelection::Review.new(run)
          end
        end
      end
    end
  end
end
