# frozen_string_literal: true

module MeetingRequests
  class CreateService
    def self.call(reviewer:, company:, purpose:, report_id: nil, reviewer_outreach_id: nil, desired_roles: [], duration_minutes: 30, urgency: "normal", proposed_windows: [])
      new(
        reviewer: reviewer,
        company: company,
        purpose: purpose,
        report_id: report_id,
        reviewer_outreach_id: reviewer_outreach_id,
        desired_roles: desired_roles,
        duration_minutes: duration_minutes,
        urgency: urgency,
        proposed_windows: proposed_windows
      ).call
    end

    def initialize(reviewer:, company:, purpose:, report_id: nil, reviewer_outreach_id: nil, desired_roles: [], duration_minutes: 30, urgency: "normal", proposed_windows: [])
      @reviewer = reviewer
      @company = company
      @purpose = purpose
      @report_id = report_id
      @reviewer_outreach_id = reviewer_outreach_id
      @desired_roles = desired_roles
      @duration_minutes = duration_minutes
      @urgency = urgency
      @proposed_windows = proposed_windows
    end

    def call
      meeting = MeetingRequest.create!(
        company: @company,
        report_id: @report_id,
        reviewer_user: @reviewer,
        reviewer_outreach_id: @reviewer_outreach_id,
        purpose: @purpose,
        desired_roles: Array(@desired_roles),
        duration_minutes: @duration_minutes,
        urgency: @urgency,
        proposed_windows: Array(@proposed_windows),
        status: "pending_admin"
      )
      meeting.append_audit!("created", actor: @reviewer, note: "Awaiting company admin approval")

      admins = @company.company_users.where(role: "company_admin", status: "active")
      NotificationService.notify(
        type: :meeting_request_pending,
        company: @company,
        recipients: admins,
        title: "Meeting request pending approval",
        body: @purpose.to_s.truncate(200),
        action_url: "#{NotificationService.app_host}/company/meeting-requests/#{meeting.id}",
        metadata: { meeting_request_id: meeting.id }
      )

      meeting
    end
  end
end
