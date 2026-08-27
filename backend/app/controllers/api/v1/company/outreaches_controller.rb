# frozen_string_literal: true

module Api
  module V1
    module Company
      class OutreachesController < BaseController
        before_action :require_company_admin!, only: %i[approve decline answer]

        def index
          outreaches = ::ConsultantOutreach.where(company_id: current_company.id).order(created_at: :desc)
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
          unless outreach.status.in?(%w[sent replied approved queued])
            return render json: { error: "Outreach cannot be answered in status #{outreach.status}" },
                           status: :unprocessable_entity
          end

          body = params.require(:body).to_s.strip
          return render json: { error: "Answer body is required" }, status: :unprocessable_entity if body.blank?

          reply = Outreaches::RecordReplyService.call(
            outreach: outreach,
            body: body,
            channel: params[:channel].presence || "portal",
            company_user: current_company_user
          )
          outreach.update!(status: "closed")
          outreach.append_audit!("answered", actor: current_company_user, note: "Closed via portal answer")

          render json: {
            outreach: outreach_json(outreach.reload),
            reply: reply_json(reply)
          }
        end

        private

        def find_outreach!
          ::ConsultantOutreach.where(company_id: current_company.id).find(params[:id])
        end

        def require_company_admin!
          return if current_company_user.company_admin?

          render json: { error: "Forbidden" }, status: :forbidden
        end

        def outreach_json(o)
          {
            id: o.id,
            report_id: o.report_id,
            consultant_user_id: o.consultant_user_id,
            consultant_name: o.consultant_user&.name,
            employee_id: o.employee_id,
            recipient_type: o.recipient_type,
            recipient_id: o.recipient_id,
            recipient_name: recipient_name_for(o),
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
            replies: o.consultant_outreach_replies.order(:received_at).map { |r| reply_json(r) },
            created_at: o.created_at,
            updated_at: o.updated_at
          }
        end

        def recipient_name_for(o)
          if o.recipient_type == "company_admin"
            CompanyUser.find_by(id: o.recipient_id)&.name || current_company_user&.name
          else
            o.employee&.display_name || o.employee&.name
          end
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
