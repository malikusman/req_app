# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class InfoRequestsController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          requests = policy_scope(::ReviewerInfoRequest).where(company_id: company.id).order(created_at: :desc)
          outreaches = ::ReviewerOutreach
            .where(company_id: company.id, reviewer_user_id: current_reviewer_user.id)
            .order(created_at: :desc)
          render json: {
            info_requests: requests.map { |r| request_json(r) },
            outreaches: outreaches.map { |o|
              {
                id: o.id,
                body: o.body,
                status: o.status,
                sent_at: o.sent_at,
                employee_id: o.employee_id,
                report_id: o.report_id,
                purpose: o.purpose,
                channel: o.channel,
                created_at: o.created_at
              }
            }
          }
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

          # Admin-gated clarification: do not send to employees until company admin approves.
          outreach = Outreaches::CreateService.call(
            reviewer: current_reviewer_user,
            company: company,
            body: params.require(:body),
            purpose: "clarification",
            channel: params[:channel].presence || "whatsapp",
            employee_id: employee.id,
            recipient_type: "employee",
            report_id: params[:report_id],
            reason: params[:reason]
          )

          render json: {
            info_request: {
              id: outreach.id,
              body: outreach.body,
              status: outreach.status,
              sent_at: outreach.sent_at,
              employee_id: outreach.employee_id,
              report_id: outreach.report_id,
              outreach: true
            },
            outreach: {
              id: outreach.id,
              status: outreach.status,
              message: "Clarification queued for company admin approval before delivery."
            }
          }, status: :created
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
