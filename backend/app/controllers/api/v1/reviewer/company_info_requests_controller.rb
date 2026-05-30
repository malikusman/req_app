# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class CompanyInfoRequestsController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          requests = policy_scope(CompanyInfoRequest).where(company_id: company.id).recent_first
          render json: { info_requests: requests.map { |r| request_json(r) } }
        end

        def create
          company = policy_scope(::Company).find(params[:company_id])
          authorize CompanyInfoRequest.new(company: company), :create?

          request = ::CompanyInfoRequests::CreateService.call(
            company: company,
            requested_by: current_reviewer_user,
            subject: params.require(:subject),
            body: params.require(:body),
            profile_section: params[:profile_section],
            due_at: params[:due_at]
          )

          render json: { info_request: request_json(request) }, status: :created
        end

        def close
          request = policy_scope(CompanyInfoRequest).find(params[:id])
          authorize request, :close?
          request.update!(status: "closed", closed_at: Time.current)
          render json: { info_request: request_json(request) }
        end

        private

        def request_json(request)
          {
            id: request.id,
            subject: request.subject,
            body: request.body,
            status: request.status,
            profile_section: request.profile_section,
            due_at: request.due_at,
            created_at: request.created_at
          }
        end
      end
    end
  end
end
