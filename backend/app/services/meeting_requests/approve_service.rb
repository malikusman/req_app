# frozen_string_literal: true

module MeetingRequests
  class ApproveService
    def self.call(meeting_request:, company_user:, selected_participant_ids: [], scheduled_at: nil, meeting_link: nil, admin_note: nil)
      new(
        meeting_request: meeting_request,
        company_user: company_user,
        selected_participant_ids: selected_participant_ids,
        scheduled_at: scheduled_at,
        meeting_link: meeting_link,
        admin_note: admin_note
      ).call
    end

    def initialize(meeting_request:, company_user:, selected_participant_ids: [], scheduled_at: nil, meeting_link: nil, admin_note: nil)
      @meeting = meeting_request
      @company_user = company_user
      @selected_participant_ids = selected_participant_ids
      @scheduled_at = scheduled_at
      @meeting_link = meeting_link
      @admin_note = admin_note
    end

    def call
      raise ArgumentError, "Meeting request is not pending admin" unless @meeting.pending_admin?
      raise ArgumentError, "Company user must belong to meeting company" unless @company_user.company_id == @meeting.company_id

      status = @scheduled_at.present? ? "scheduled" : "approved"

      @meeting.update!(
        status: status,
        approved_by_company_user: @company_user,
        selected_participant_ids: Array(@selected_participant_ids),
        scheduled_at: @scheduled_at,
        meeting_link: @meeting_link,
        admin_note: @admin_note
      )
      @meeting.append_audit!("approved", actor: @company_user, note: @admin_note)

      NotificationService.notify(
        type: :meeting_request_approved,
        company: @meeting.company,
        recipients: @meeting.reviewer_user,
        title: "Meeting request approved",
        body: @meeting.purpose.to_s.truncate(200),
        action_url: "#{NotificationService.app_host}/reviewer/companies/#{@meeting.company_id}/meeting-requests/#{@meeting.id}",
        metadata: { meeting_request_id: @meeting.id }
      )

      @meeting
    end
  end
end
