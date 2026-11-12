# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class DeepDivePlansController < BaseController
        rescue_from DeepDivePlans::Workflow::Conflict do |error|
          render json: { error: error.message }, status: :conflict
        end

        rescue_from DeepDivePlans::Invalid do |error|
          render json: { error: error.message }, status: 422
        end

        def index
          render json: workflow.index
        end

        def show
          render json: workflow.read(params[:id], params[:version])
        end

        def generate
          render json: workflow.generate(params[:id])
        end

        def update
          render json: workflow.revise(params[:id], request.request_parameters)
        end

        def approve
          render json: workflow.revise(params[:id], request.request_parameters, approve: true)
        end

        private

        def workflow
          company = policy_scope(::Company).find(params[:company_id])
          run = policy_scope(::TaskIntelligenceRun).where(company: company).find(params[:task_intelligence_run_id])
          DeepDivePlans::Workflow.new(run, current_consultant_user)
        end
      end
    end
  end
end
