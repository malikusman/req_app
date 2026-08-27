# frozen_string_literal: true

module Outreaches
  class DeliverService
    def self.call(outreach:)
      new(outreach: outreach).call
    end

    def initialize(outreach:)
      @outreach = outreach
    end

    def call
      # Idempotent: deferred Sidekiq jobs must not fail after a successful send/reply.
      return @outreach if @outreach.status.in?(%w[sent replied])

      raise ArgumentError, "Outreach not approved" unless @outreach.status.in?(%w[approved queued])

      @outreach.update!(status: "queued")
      body = @outreach.edited_body.presence || @outreach.body

      case @outreach.channel
      when "whatsapp"
        deliver_whatsapp!(body)
      when "email"
        deliver_email!(body)
      when "portal"
        @outreach.update!(status: "sent", sent_at: Time.current)
      else
        raise ArgumentError, "Unsupported channel #{@outreach.channel}"
      end

      @outreach.append_audit!("sent", actor: @outreach.approved_by_company_user || @outreach.reviewer_user)
      @outreach
    rescue ArgumentError => e
      raise if e.message == "Outreach not approved"

      @outreach.update!(status: "failed")
      @outreach.append_audit!("failed", actor: @outreach.reviewer_user, note: e.message)
      raise
    rescue StandardError => e
      @outreach.update!(status: "failed")
      @outreach.append_audit!("failed", actor: @outreach.reviewer_user, note: e.message)
      raise
    end

    private

    def deliver_whatsapp!(body)
      employee = @outreach.employee
      raise ArgumentError, "Employee required for WhatsApp outreach" unless employee

      conversation = @outreach.conversation || employee.conversations.order(updated_at: :desc).first
      raise ArgumentError, "No conversation for employee" unless conversation

      client = Whatsapp::MetaClient.new
      within_window = conversation.last_activity_at.present? && conversation.last_activity_at > 24.hours.ago

      response = if client.configured?
                   if within_window
                     client.send_text(to: employee.phone_e164, body: body)
                   else
                     client.send_reviewer_followup_template(
                       to: employee.phone_e164,
                       employee_name: employee.display_name || "there",
                       company_name: @outreach.company.display_name || @outreach.company.name
                     )
                     client.respond_to?(:send_text) ? client.send_text(to: employee.phone_e164, body: body) : nil
                   end
                 else
                   Rails.logger.info("[Outreach WhatsApp dev] to=#{employee.phone_e164} body=#{body}")
                   { "messages" => [{ "id" => "dev-#{SecureRandom.hex(8)}" }] }
                 end

      meta_id = response&.dig("messages", 0, "id")
      message = conversation.messages.create!(
        direction: "outbound",
        message_type: "text",
        body: body,
        external_id: meta_id,
        reviewer_followup: true,
        track: "consultant_followup",
        track_ref: @outreach,
        raw_payload: { "reviewer_outreach_id" => @outreach.id }
      )

      @outreach.update!(status: "sent", sent_at: Time.current, meta_message_id: meta_id, message_id: message.id,
                        conversation: conversation)
    end

    def deliver_email!(body)
      employee = @outreach.employee
      raise ArgumentError, "Employee required for email outreach" unless employee
      raise ArgumentError, "Employee email missing" if employee.email.blank?

      raw_token = SecureRandom.urlsafe_base64(32)
      @outreach.update!(
        reply_token_digest: Digest::SHA256.hexdigest(raw_token),
        status: "sent",
        sent_at: Time.current
      )
      OutreachMailer.request_email(@outreach, raw_token).deliver_later
    end
  end
end
