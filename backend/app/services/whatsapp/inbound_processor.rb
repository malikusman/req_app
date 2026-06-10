# frozen_string_literal: true

module Whatsapp
  class InboundProcessor
    def initialize(payload)
      @payload = payload
      @client = MetaClient.new
    end

    def process
      entries = @payload.dig("entry") || []
      entries.each do |entry|
        (entry["changes"] || []).each do |change|
          process_change(change)
        end
      end
    end

    private

    def process_change(change)
      value = change["value"] || {}
      (value["messages"] || []).each { |msg| process_message(msg, value) }
      (value["statuses"] || []).each { |status| process_status(status) }
    end

    def process_message(msg, value)
      wamid = msg["id"]
      return if wamid.blank? || WebhookEvent.exists?(external_id: wamid)

      WebhookEvent.create!(
        external_id: wamid,
        payload: msg,
        status: "processing"
      )

      phone = "+#{msg['from']}"
      employee = Employee.find_by(phone_e164: phone)

      unless employee
        handle_unknown_phone(phone, msg, wamid)
        return
      end

      conversation = active_conversation_for(employee)

      if media_message?(msg)
        handle_media_message(employee: employee, conversation: conversation, msg: msg)
      else
        text = extract_text(msg)
        route_inbound_text(employee: employee, conversation: conversation, text: text, external_id: wamid) if text.present?
      end

      WebhookEvent.where(external_id: wamid).update_all(status: "processed", processed_at: Time.current)
    rescue StandardError => e
      Rails.logger.error("[WhatsApp] process_message failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      WebhookEvent.where(external_id: wamid).update_all(status: "failed") if wamid
      raise
    end

    def process_status(status)
      meta_id = status["id"]
      invitation = EmployeeInvitation.find_by(meta_message_id: meta_id)
      return unless invitation

      case status["status"]
      when "delivered"
        invitation.update!(delivery_status: "delivered")
      when "read"
        invitation.update!(delivery_status: "delivered")
      when "failed"
        invitation.update!(delivery_status: "failed", error_message: status.dig("errors", 0, "title"))
        WhatsappDeliveryMetric.record!("template_failed", metadata: { meta_id: meta_id })
      end
    end

    def extract_text(msg)
      case msg["type"]
      when "text"
        msg.dig("text", "body")
      when "interactive"
        msg.dig("interactive", "button_reply", "title") || msg.dig("interactive", "list_reply", "title")
      else
        nil
      end
    end

    def active_conversation_for(employee)
      conv = employee.conversations.where.not(status: "abandoned").order(created_at: :desc).first
      return conv if conv

      employee.conversations.create!(
        company: employee.company,
        status: "onboarding",
        started_at: Time.current,
        last_activity_at: Time.current
      )
    end

    def handle_unknown_phone(phone, msg, wamid)
      WebhookEvent.where(external_id: wamid).update_all(status: "processed", processed_at: Time.current) if wamid

      company_id = guess_company_from_recent_invite(phone)
      if company_id
        AccessCodeVerificationAttempt.create!(
          company_id: company_id,
          phone_e164: phone,
          success: false,
          failure_reason: "unknown_phone"
        )
      end

      return unless @client.configured?

      @client.send_text(
        to: phone,
        body: "Hi! You're not registered yet. Ask your company admin for a discovery invitation."
      )
    end

    def media_message?(msg)
      %w[audio image document].include?(msg["type"])
    end

    def handle_media_message(employee:, conversation:, msg:)
      if conversation.profiling?
        send_profiling_media_notice(employee)
        return
      end

      unless conversation.discovery? || employee.onboarding_step == "verified"
        send_onboarding_media_notice(employee)
        return
      end

      MultimodalInboundHandler.new(employee: employee, conversation: conversation, msg: msg, client: @client).handle
    end

    def send_profiling_media_notice(employee)
      return unless @client.configured?

      @client.send_text(
        to: employee.phone_e164,
        body: "Please answer with a short text message for now. Once we start the interview you can send voice notes and images."
      )
    end

    def send_onboarding_media_notice(employee)
      return unless @client.configured?

      @client.send_text(
        to: employee.phone_e164,
        body: "Please complete onboarding with text messages first. After verification you can send voice notes and images."
      )
    end

    def route_inbound_text(employee:, conversation:, text:, external_id:)
      if ReviewerInfoRequest.open_for_employee(employee.id)
        handled = Whatsapp::ReviewerFollowupHandler.new(
          employee: employee,
          conversation: conversation,
          text: text,
          external_id: external_id,
          client: @client
        ).handle
        return if handled
      end

      if conversation.profiling?
        Whatsapp::ProfilingHandler.new(employee: employee, conversation: conversation, client: @client)
                                   .handle_inbound_text(text, external_id: external_id)
      elsif conversation.discovery? || employee.onboarding_step == "verified"
        Whatsapp::DiscoveryHandler.new(employee: employee, conversation: conversation, client: @client)
                                   .handle_inbound_text(text, external_id: external_id)
      else
        OnboardingHandler.new(employee: employee, conversation: conversation, client: @client).handle_inbound_text(text)
      end
    end

    def guess_company_from_recent_invite(phone)
      EmployeeInvitation.where(phone_e164: phone).order(created_at: :desc).limit(1).pick(:company_id)
    end
  end
end
