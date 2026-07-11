# frozen_string_literal: true

module Api
  module V1
    module Company
      class OutreachesController < BaseController
        before_action :require_company_admin!, only: %i[approve decline answer]

        def index
          outreaches = ::ReviewerOutreach.where(company_id: current_company.id).order(created_at: :desc)
          render json: { outreaches: outreaches.map { |o| outreach_json(o) } }
        end

        def show
          outreach = find_outreach!
          render json: { outreach: outreach_json(outreach) }
        end

        def approve
          outreach = find_outreach!
          authorize outreach, :approve?
          Outreaches::ApproveService.call(
            outreach: outreach,
            admin: current_company_user,
            edited_body: params[:edited_body],
            note: params[:admin_note] || params[:note],
            employee_id: params[:employee_id]
          )
          render json: { outreach: outreach_json(outreach.reload) }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def decline
          outreach = find_outreach!
          authorize outreach, :decline?
          Outreaches::DeclineService.call(
            outreach: outreach,
            admin: current_company_user,
            note: params[:admin_note] || params[:note]
          )
          render json: { outreach: outreach_json(outreach.reload) }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def answer
          outreach = find_outreach!
          authorize outreach, :answer?
          body = params.require(:body)

          reply = nil
          ActiveRecord::Base.transaction do
            reply = ReviewerOutreachReply.create!(
              reviewer_outreach: outreach,
              channel: params[:channel].presence || "portal",
              body: body,
              company_user: current_company_user,
              received_at: Time.current
            )
            outreach.update!(status: "closed")
            outreach.append_audit!("answered", actor: current_company_user, note: "Closed via portal answer")
          end

          render json: {
            outreach: outreach_json(outreach.reload),
            reply: reply_json(reply)
          }
        end

        private

        def find_outreach!
          ::ReviewerOutreach.where(company_id: current_company.id).find(params[:id])
        end

        def require_company_admin!
          return if current_company_user.company_admin?

          render json: { error: "Forbidden" }, status: :forbidden
        end

        def outreach_json(o)
          {
            id: o.id,
            report_id: o.report_id,
            reviewer_user_id: o.reviewer_user_id,
            reviewer_name: o.reviewer_user&.name,
            employee_id: o.employee_id,
            recipient_type: o.recipient_type,
            purpose: o.purpose,
            channel: o.channel,
            status: o.status,
            body: o.body,
            edited_body: o.edited_body,
            reason: o.reason,
            section_key: o.section_key,
            requested_deadline_at: o.requested_deadline_at,
            approved_at: o.approved_at,
            declined_at: o.declined_at,
            sent_at: o.sent_at,
            admin_note: o.admin_note,
            replies: o.reviewer_outreach_replies.order(:received_at).map { |r| reply_json(r) },
            created_at: o.created_at,
            updated_at: o.updated_at
          }
        end

        def reply_json(r)
          {
            id: r.id,
            channel: r.channel,
            body: r.body,
            company_user_id: r.company_user_id,
            received_at: r.received_at,
            created_at: r.created_at
          }
        end
      end
    end
  end
end
