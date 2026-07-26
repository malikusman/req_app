# frozen_string_literal: true

module ReviewerFollowup
  # Direct WhatsApp follow-up via ReviewerInfoRequest (no admin approval gate).
  # Prefer Outreaches::CreateService for admin-gated employee asks from Clarifications.
  class SendService
    def self.call(reviewer:, employee:, body:, report: nil)
      new(reviewer: reviewer, employee: employee, body: body, report: report).call
    end

    def initialize(reviewer:, employee:, body:, report: nil)
      @reviewer = reviewer
      @employee = employee
      @company = employee.company
      @body = body
      @report = report
    end

    def call
      conversation = @employee.conversations.order(updated_at: :desc).first
      raise ArgumentError, "No conversation for employee" unless conversation

      request = ReviewerInfoRequest.create!(
        company: @company,
        report: @report,
        reviewer_user: @reviewer,
        employee: @employee,
        conversation: conversation,
        body: @body,
        status: "draft"
      )

      client = Whatsapp::MetaClient.new
      within_window = conversation.last_activity_at.present? && conversation.last_activity_at > 24.hours.ago

      response = if client.configured?
                   if within_window
                     client.send_text(to: @employee.phone_e164, body: @body)
                   else
                     client.send_reviewer_followup_template(
                       to: @employee.phone_e164,
                       employee_name: @employee.display_name || "there",
                       company_name: @company.display_name || @company.name
                     )
                   end
                 else
                   Rails.logger.info("[Reviewer followup dev] to=#{@employee.phone_e164} body=#{@body}")
                   { "messages" => [{ "id" => "dev-#{SecureRandom.hex(8)}" }] }
                 end

      meta_id = response&.dig("messages", 0, "id")
      outbound = conversation.messages.create!(
        direction: "outbound",
        message_type: "text",
        body: @body,
        external_id: meta_id,
        reviewer_followup: true,
        raw_payload: { reviewer_info_request_id: request.id }
      )

      request.update!(
        status: "awaiting_reply",
        meta_message_id: meta_id,
        sent_at: Time.current
      )

      conversation.update!(last_activity_at: Time.current)
      { request: request, message: outbound }
    end
  end
end
