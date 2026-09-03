# frozen_string_literal: true

module ConsultantFollowup
  # Direct consultant follow-up via ConsultantInfoRequest (no admin approval gate).
  # Prefer Outreaches::CreateService for admin-gated employee asks from Clarifications.
  #
  # Delivers over WhatsApp or email. Email carries a tokenised reply link so an
  # employee who does not use WhatsApp — or whose 24h window has closed and who never
  # taps a template — can still answer, in a browser, into the same thread.
  class SendService
    class Undeliverable < StandardError; end

    CHANNELS = %w[whatsapp email].freeze

    def self.call(consultant:, employee:, body:, report: nil, channel: nil)
      new(consultant: consultant, employee: employee, body: body, report: report, channel: channel).call
    end

    def initialize(consultant:, employee:, body:, report: nil, channel: nil)
      @consultant = consultant
      @employee = employee
      @company = employee.company
      @body = body
      @report = report
      @requested_channel = channel.presence
    end

    def call
      conversation = @employee.conversations.order(updated_at: :desc).first
      raise ArgumentError, "No conversation for employee" unless conversation

      channel = resolve_channel
      request = ConsultantInfoRequest.create!(
        company: @company,
        report: @report,
        consultant_user: @consultant,
        employee: @employee,
        conversation: conversation,
        body: @body,
        channel: channel,
        status: "draft"
      )

      channel == "email" ? deliver_email!(request, conversation) : deliver_whatsapp!(request, conversation)
    end

    private

    # An explicit channel wins. Otherwise infer from how the employee actually does
    # discovery: Employee#preferred_channel is whatsapp | web | both, so a "web"
    # employee is a browser user — WhatsApp may not even be set up for them, and an
    # emailed link lands them exactly where they already answer.
    #
    # Then fall back on what contact details exist. Asking on a channel the employee
    # has no address for is worse than asking on their second choice.
    def resolve_channel
      preferred = if CHANNELS.include?(@requested_channel)
                    @requested_channel
                  elsif @employee.preferred_channel == "web"
                    "email"
                  else
                    "whatsapp"
                  end

      return preferred if preferred == "email" && @employee.email.present?
      return "whatsapp" if preferred == "whatsapp" && @employee.phone_e164.present?

      # Preferred channel unreachable — use whichever address we do have.
      return "whatsapp" if @employee.phone_e164.present?
      return "email" if @employee.email.present?

      raise Undeliverable, "#{@employee.display_name || 'This employee'} has no phone or email on file."
    end

    def deliver_whatsapp!(request, conversation)
      client = Whatsapp::MetaClient.new
      within_window = conversation.last_activity_at.present? && conversation.last_activity_at > 24.hours.ago

      response = if client.configured?
                   if within_window
                     client.send_text(to: @employee.phone_e164, body: @body)
                   else
                     client.send_consultant_followup_template(
                       to: @employee.phone_e164,
                       employee_name: @employee.display_name || "there",
                       company_name: @company.display_name || @company.name,
                       question: @body
                     )
                   end
                 else
                   Rails.logger.info("[Consultant followup dev] to=#{@employee.phone_e164} body=#{@body}")
                   { "messages" => [{ "id" => "dev-#{SecureRandom.hex(8)}" }] }
                 end

      meta_id = response&.dig("messages", 0, "id")
      outbound = persist_outbound!(conversation, request, channel: "whatsapp", external_id: meta_id)

      request.update!(status: "awaiting_reply", meta_message_id: meta_id, sent_at: Time.current)
      conversation.update!(last_activity_at: Time.current)
      { request: request, message: outbound }
    end

    def deliver_email!(request, conversation)
      raise Undeliverable, "No email address on file for this employee." if @employee.email.blank?

      # The raw token exists only in the email; only its digest is stored.
      raw_token = request.mint_reply_token!
      ConsultantFollowupMailer.question_email(request, raw_token).deliver_later

      outbound = persist_outbound!(conversation, request, channel: "web")
      request.update!(status: "awaiting_reply", sent_at: Time.current, email_sent_at: Time.current)
      conversation.update!(last_activity_at: Time.current)
      { request: request, message: outbound }
    end

    # Recorded on the conversation either way, so the question is visible in the
    # employee's own thread whichever channel carried it.
    def persist_outbound!(conversation, request, channel:, external_id: nil)
      conversation.messages.create!(
        direction: "outbound",
        message_type: "text",
        channel: channel,
        body: @body,
        external_id: external_id,
        consultant_followup: true,
        track: "consultant_followup",
        track_ref: request,
        raw_payload: { consultant_info_request_id: request.id, delivery_channel: request.channel }
      )
    end
  end
end
