# frozen_string_literal: true

module Api
  module V1
    module Company
      class InfoRequestsController < BaseController
        skip_before_action :require_active_subscription!, only: %i[index show create_reply]

        def index
          authorize CompanyInfoRequest, :index?
          requests = policy_scope(CompanyInfoRequest).includes(:requested_by, :company_info_request_replies)
          open_count = requests.where(status: "open").count
          render json: {
            open_count: open_count,
            info_requests: requests.limit(50).map { |r| request_json(r, include_replies: false) }
          }
        end

        def show
          request = policy_scope(CompanyInfoRequest).find(params[:id])
          authorize request, :show?
          render json: { info_request: request_json(request, include_replies: true) }
        end

        def create_reply
          request = policy_scope(CompanyInfoRequest).find(params[:id])
          authorize request, :reply?

          reply = ::CompanyInfoRequests::ReplyService.call(
            request: request,
            sender: current_company_user,
            body: params.require(:body),
            file: params[:file],
            uploaded_by: current_company_user
          )

          render json: { reply: reply_json(reply), info_request: request_json(request.reload, include_replies: true) }, status: :created
        end

        private

        def request_json(request, include_replies:)
          payload = {
            id: request.id,
            subject: request.subject,
            body: request.body,
            status: request.status,
            profile_section: request.profile_section,
            due_at: request.due_at,
            closed_at: request.closed_at,
            created_at: request.created_at,
            requested_by_name: request.requested_by_name,
            requested_by_role: request.requested_by_role_label
          }
          if include_replies
            payload[:replies] = request.company_info_request_replies.order(:created_at).map { |r| reply_json(r) }
          end
          payload
        end

        def reply_json(reply)
          {
            id: reply.id,
            body: reply.body,
            sender_type: reply.sender_type,
            created_at: reply.created_at,
            document: reply.document ? { id: reply.document.id, filename: reply.document.filename, status: reply.document.status } : nil
          }
        end
      end
    end
  end
end
