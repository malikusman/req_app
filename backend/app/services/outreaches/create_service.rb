# frozen_string_literal: true

module Outreaches
  # Creates reviewer → company_admin (portal) or reviewer → employee (WhatsApp) outreaches.
  # Employee outreaches require company-admin approval before DeliverOutreachJob.
  #
  # Note: workspace "Ask employee" via ReviewDiscussions may use ReviewerFollowup::SendService
  # (ReviewerInfoRequest) instead. Prefer this service for admin-gated employee asks;
  # prefer SendService for evidence-anchored direct follow-ups until those paths are merged.
  class CreateService
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(reviewer:, company:, body:, purpose: "clarification", channel: "whatsapp",
                   employee_id: nil, recipient_type: "employee", recipient_id: nil, report_id: nil,
                   section_key: nil, anchor_type: nil, anchor_id: nil, reason: nil,
                   requested_deadline_at: nil)
      @reviewer = reviewer
      @company = company
      @body = body
      @purpose = purpose
      @channel = channel
      @employee_id = employee_id
      @recipient_type = recipient_type.to_s.presence || "employee"
      @recipient_id = recipient_id
      @report_id = report_id
      @section_key = section_key
      @anchor_type = anchor_type
      @anchor_id = anchor_id
      @reason = reason
      @requested_deadline_at = requested_deadline_at
    end

    def call
      unless ReviewerOutreach::RECIPIENT_TYPES.include?(@recipient_type)
        raise ArgumentError, "recipient_type must be employee or company_admin"
      end

      if @recipient_type == "company_admin"
        create_for_company_admin!
      else
        create_for_employee!
      end
    end

    private

    def create_for_employee!
      employee = @employee_id.present? ? @company.employees.find(@employee_id) : nil
      conversation = employee&.conversations&.order(updated_at: :desc)&.first

      outreach = ReviewerOutreach.create!(
        company: @company,
        report_id: @report_id,
        reviewer_user: @reviewer,
        recipient_type: "employee",
        recipient_id: employee&.id,
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

    def create_for_company_admin!
      admin = resolve_company_admin!
      outreach = ReviewerOutreach.create!(
        company: @company,
        report_id: @report_id,
        reviewer_user: @reviewer,
        recipient_type: "company_admin",
        recipient_id: admin.id,
        employee: nil,
        conversation: nil,
        purpose: @purpose,
        channel: "portal",
        status: "sent",
        sent_at: Time.current,
        body: @body,
        reason: @reason,
        section_key: @section_key,
        anchor_type: @anchor_type,
        anchor_id: @anchor_id,
        requested_deadline_at: @requested_deadline_at
      )
      outreach.append_audit!("created", actor: @reviewer, note: "Sent to company admin via portal (no approval gate)")
      outreach.append_audit!("sent", actor: @reviewer, note: "Delivered to Clarifications inbox")

      if NotificationService.respond_to?(:notify_outreach_received)
        NotificationService.notify_outreach_received(outreach: outreach, recipient: admin)
      else
        Notification.create!(
          company: @company,
          recipient: admin,
          notification_type: "outreach_received",
          title: "Reviewer question for your company",
          body: @body.to_s.truncate(200),
          action_url: "/company/outreaches/#{outreach.id}",
          metadata: { "outreach_id" => outreach.id }
        )
      end

      outreach
    end

    def resolve_company_admin!
      scope = @company.company_users.where(role: "company_admin", status: "active")
      admin = if @recipient_id.present?
                scope.find_by(id: @recipient_id)
              else
                scope.order(:created_at).first
              end
      raise ArgumentError, "No active company admin found" unless admin

      admin
    end
  end
end
