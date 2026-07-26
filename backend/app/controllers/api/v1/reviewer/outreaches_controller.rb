# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class OutreachesController < BaseController
        def index
          company = find_assigned_company!
          outreaches = ::ReviewerOutreach
            .where(company_id: company.id)
            .includes(:reviewer_outreach_replies, :reviewer_user, :employee)
            .order(created_at: :desc)
          render json: { outreaches: outreaches.map { |o| outreach_json(o) } }
        end

        def show
          company = find_assigned_company!
          outreach = ::ReviewerOutreach
            .where(company_id: company.id)
            .includes(:reviewer_outreach_replies, :reviewer_user, :employee)
            .find(params[:id])
          render json: { outreach: outreach_json(outreach) }
        end

        def create
          company = find_assigned_company!
          outreach = Outreaches::CreateService.call(
            reviewer: current_reviewer_user,
            company: company,
            body: params.require(:body),
            purpose: params[:purpose].presence || "clarification",
            channel: params[:channel].presence || "whatsapp",
            recipient_type: params[:recipient_type].presence || "employee",
            recipient_id: params[:recipient_id],
            employee_id: params[:employee_id],
            report_id: params[:report_id],
            section_key: params[:section_key],
            anchor_type: params[:anchor_type],
            anchor_id: params[:anchor_id],
            reason: params[:reason],
            requested_deadline_at: params[:requested_deadline_at]
          )
          render json: { outreach: outreach_json(outreach) }, status: :created
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def find_assigned_company!
          company = ::Company.find(params[:company_id])
          unless assigned_company_ids.include?(company.id)
            raise ActiveRecord::RecordNotFound
          end

          company
        end

        def outreach_json(o)
          {
            id: o.id,
            company_id: o.company_id,
            report_id: o.report_id,
            reviewer_user_id: o.reviewer_user_id,
            reviewer_name: o.reviewer_user&.name,
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
            anchor_type: o.anchor_type,
            anchor_id: o.anchor_id,
            requested_deadline_at: o.requested_deadline_at,
            approved_at: o.approved_at,
            declined_at: o.declined_at,
            sent_at: o.sent_at,
            admin_note: o.admin_note,
            replies: o.reviewer_outreach_replies.sort_by(&:received_at).map { |r| reply_json(r) },
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

        def recipient_name_for(o)
          if o.recipient_type == "company_admin"
            CompanyUser.find_by(id: o.recipient_id)&.name
          else
            o.employee&.display_name || o.employee&.name
          end
        end
      end
    end
  end
end
