# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class InfoRequestsController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          requests = policy_scope(::ReviewerInfoRequest).where(company_id: company.id).order(created_at: :desc)
          render json: { info_requests: requests.map { |r| request_json(r) } }
        end

        def show
          request = policy_scope(::ReviewerInfoRequest).find(params[:id])
          authorize request, :show?
          render json: { info_request: request_json(request) }
        end

        def create
          company = policy_scope(::Company).find(params[:company_id])
          employee = company.employees.find(params[:employee_id])
          authorize ReviewerInfoRequest.new(company: company), :create?

          result = ReviewerFollowup::SendService.call(
            reviewer: current_reviewer_user,
            employee: employee,
            body: params.require(:body),
            report: params[:report_id].present? ? company.reports.find(params[:report_id]) : nil
          )

          render json: { info_request: request_json(result[:request]) }, status: :created
        end

        def thread
          company = policy_scope(::Company).find(params[:company_id])
          employee = company.employees.find(params[:employee_id])
          requests = policy_scope(::ReviewerInfoRequest)
            .where(company_id: company.id, employee_id: employee.id, reviewer_user_id: current_reviewer_user.id)
            .includes(:reviewer_info_replies)
            .order(created_at: :asc)

          render json: {
            employee: { id: employee.id, display_name: employee.display_name },
            threads: requests.map { |r| thread_json(r) }
          }
        end

        private

        def request_json(r)
          {
            id: r.id,
            body: r.body,
            status: r.status,
            sent_at: r.sent_at,
            employee_id: r.employee_id,
            report_id: r.report_id
          }
        end

        def thread_json(r)
          request_json(r).merge(
            replies: r.reviewer_info_replies.order(:received_at).map { |reply|
              {
                id: reply.id,
                body: reply.body,
                received_at: reply.received_at,
                message_id: reply.message_id
              }
            }
          )
        end
      end
    end
  end
end
