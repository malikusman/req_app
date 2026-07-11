# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class MeetingRequestsController < BaseController
        def index
          company = find_assigned_company!
          meetings = MeetingRequest.where(company_id: company.id).order(created_at: :desc)
          render json: { meeting_requests: meetings.map { |m| meeting_json(m) } }
        end

        def show
          company = find_assigned_company!
          meeting = MeetingRequest.where(company_id: company.id).find(params[:id])
          authorize meeting, :show?
          render json: { meeting_request: meeting_json(meeting) }
        end

        def create
          company = find_assigned_company!
          authorize MeetingRequest.new(company: company), :create?
          meeting = MeetingRequests::CreateService.call(
            reviewer: current_reviewer_user,
            company: company,
            purpose: params.require(:purpose),
            report_id: params[:report_id],
            reviewer_outreach_id: params[:reviewer_outreach_id],
            desired_roles: params[:desired_roles] || [],
            duration_minutes: params[:duration_minutes].presence || 30,
            urgency: params[:urgency].presence || "normal",
            proposed_windows: params[:proposed_windows] || []
          )
          render json: { meeting_request: meeting_json(meeting) }, status: :created
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

        def meeting_json(m)
          {
            id: m.id,
            company_id: m.company_id,
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
