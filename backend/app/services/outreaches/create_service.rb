# frozen_string_literal: true

module Outreaches
  class CreateService
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(reviewer:, company:, body:, purpose: "clarification", channel: "whatsapp",
                   employee_id: nil, recipient_type: "employee", report_id: nil, section_key: nil,
                   anchor_type: nil, anchor_id: nil, reason: nil, requested_deadline_at: nil)
      @reviewer = reviewer
      @company = company
      @body = body
      @purpose = purpose
      @channel = channel
      @employee_id = employee_id
      @recipient_type = recipient_type
      @report_id = report_id
      @section_key = section_key
      @anchor_type = anchor_type
      @anchor_id = anchor_id
      @reason = reason
      @requested_deadline_at = requested_deadline_at
    end

    def call
      employee = @employee_id.present? ? @company.employees.find(@employee_id) : nil
      conversation = employee&.conversations&.order(updated_at: :desc)&.first

      outreach = ReviewerOutreach.create!(
        company: @company,
        report_id: @report_id,
        reviewer_user: @reviewer,
        recipient_type: @recipient_type,
        recipient_id: @recipient_type == "employee" ? employee&.id : nil,
        employee: employee,
        conversation: conversation,
        purpose: @purpose,
        channel: @channel,
        status: "pending_admin_approval",
        body: @body,
        reason: @reason,
        section_key: @section_key,
        anchor_type: @anchor_type,
        anchor_id: @anchor_id,
        requested_deadline_at: @requested_deadline_at
      )
      outreach.append_audit!("created", actor: @reviewer, note: "Awaiting company admin approval")

      if NotificationService.respond_to?(:notify_outreach_pending_admin)
        NotificationService.notify_outreach_pending_admin(outreach: outreach)
      else
        @company.company_users.where(role: "company_admin", status: "active").find_each do |admin|
          Notification.create!(
            company: @company,
            recipient: admin,
            notification_type: "outreach_pending_admin",
            title: "Reviewer clarification needs approval",
            body: "#{@reviewer.name} asked to contact #{employee&.display_name || 'the company'}.",
            action_url: "/company/outreaches/#{outreach.id}",
            metadata: { "outreach_id" => outreach.id }
          )
        end
      end

      outreach
    end
  end
end
