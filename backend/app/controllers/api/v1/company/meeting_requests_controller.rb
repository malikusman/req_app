# frozen_string_literal: true

module Api
  module V1
    module Company
      class MeetingRequestsController < BaseController
        before_action :require_company_admin!, only: %i[approve decline]

        def index
          meetings = MeetingRequest.where(company_id: current_company.id).order(created_at: :desc)
          render json: { meeting_requests: meetings.map { |m| meeting_json(m) } }
        end

        def show
          meeting = MeetingRequest.where(company_id: current_company.id).find(params[:id])
          authorize meeting, :show?
          render json: { meeting_request: meeting_json(meeting) }
        end

        def approve
          meeting = MeetingRequest.where(company_id: current_company.id).find(params[:id])
          authorize meeting, :approve?
          MeetingRequests::ApproveService.call(
            meeting_request: meeting,
            company_user: current_company_user,
            selected_participant_ids: params[:selected_participant_ids] || [],
            scheduled_at: params[:scheduled_at],
            meeting_link: params[:meeting_link],
            admin_note: params[:admin_note] || params[:note]
          )
          render json: { meeting_request: meeting_json(meeting.reload) }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def decline
          meeting = MeetingRequest.where(company_id: current_company.id).find(params[:id])
          authorize meeting, :decline?
          raise ArgumentError, "Meeting request is not pending admin" unless meeting.pending_admin?

          meeting.update!(
            status: "declined",
            approved_by_company_user: current_company_user,
            admin_note: params[:admin_note] || params[:note]
          )
          meeting.append_audit!("declined", actor: current_company_user, note: params[:admin_note] || params[:note])
          render json: { meeting_request: meeting_json(meeting.reload) }
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def require_company_admin!
          return if current_company_user.company_admin?

          render json: { error: "Forbidden" }, status: :forbidden
        end

        def meeting_json(m)
          {
            id: m.id,
            report_id: m.report_id,
            reviewer_user_id: m.reviewer_user_id,
            reviewer_outreach_id: m.reviewer_outreach_id,
            purpose: m.purpose,
            desired_roles: m.desired_roles,
            duration_minutes: m.duration_minutes,
            urgency: m.urgency,
            proposed_windows: m.proposed_windows,
            status: m.status,
            selected_participant_ids: m.selected_participant_ids,
            scheduled_at: m.scheduled_at,
            meeting_link: m.meeting_link,
            admin_note: m.admin_note,
            outcome_note: m.outcome_note,
            created_at: m.created_at,
            updated_at: m.updated_at
          }
        end
      end
    end
  end
end
