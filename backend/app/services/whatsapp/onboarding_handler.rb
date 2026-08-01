# frozen_string_literal: true

module Whatsapp
  class OnboardingHandler
    def initialize(employee:, conversation:, client: MetaClient.new, channel: "whatsapp")
      @employee = employee
      @company = employee.company
      @conversation = conversation
      @client = client
      @channel = channel
    end

    def prompt_consent_if_needed!
      return unless @employee.onboarding_step == "awaiting_consent"
      return if consent_already_sent?

      send_consent_message
    end

    def handle_inbound_text(text, external_id: nil)
      text = text.to_s.strip
      return handle_opt_out if opt_out?(text)

      mark_started_if_needed
      detect_and_set_language(text)
      @conversation.touch_activity!

      case @employee.onboarding_step
      when "awaiting_name"
        if name_prompt_pending?
          persist_message(direction: "inbound", body: text)
          mark_name_prompt_sent!
          send_text(greeting_for_unknown_step)
          return
        end
        handle_name(text)
      when "awaiting_company"
        handle_company(text)
      when "awaiting_consent"
        handle_consent(text, external_id: external_id)
      when "verified"
        handle_post_verification(text)
      else
        send_text(greeting_for_unknown_step)
      end
    end

    private

    def handle_opt_out
      @employee.update!(participation_status: "declined")
      send_text(opt_out_message)
    end

    def opt_out?(text)
      %w[stop unsubscribe cancel].include?(text.downcase)
    end

    def mark_started_if_needed
      return unless @employee.participation_status == "invited"

      @employee.update!(participation_status: "started", started_at: Time.current)
      NotificationService.notify_interview_started(company: @company, employee: @employee)
    end

    def handle_name(text)
      @employee.update!(display_name: text, onboarding_step: "awaiting_company")
      persist_message(direction: "inbound", body: text)
      if @employee.invited_at.present?
        @employee.update!(onboarding_step: "awaiting_consent", verified_at: Time.current)
        send_consent_message
      else
        send_text("Thanks! Which company do you work for?")
      end
    end

    def handle_company(text)
      persist_message(direction: "inbound", body: text)
      company_match = ::Company.where("LOWER(name) = ? OR LOWER(display_name) = ?",
                                      text.downcase, text.downcase).first
      company_match ||= @company if text.downcase.include?(@company.name.downcase)

      unless company_match && company_match.id == @company.id
        send_text("I couldn't find that company. Please try again with your company name.")
        return
      end

      @employee.update!(onboarding_step: "awaiting_consent", verified_at: Time.current)
      send_consent_message
    end

    def handle_consent(text, external_id: nil)
      persist_message(direction: "inbound", body: text, external_id: external_id)
      consent = active_consent

      if !consent_already_sent? && !consent_confirmed?(text, consent)
        send_consent_message
        return
      end

      if consent_confirmed?(text, consent)
        unless Subscriptions::ConversationLimitEnforcer.can_start_discovery?(company: @company)
          send_text("Discovery is temporarily unavailable for your organization. Please contact your admin.")
          return
        end

        @employee.update!(
          onboarding_step: "verified",
          consent_given_at: Time.current,
          consent_text_version: consent.version
        )
        lang = LanguageDetector.detect(text)
        @employee.update!(preferred_language: lang) if @employee.preferred_language.blank?

        if Whatsapp::ProfilingHandler.enabled?(@company) && !@employee.profile_complete?
          @conversation.update!(status: "profiling", started_at: Time.current)
          Subscriptions::ConversationLimitEnforcer.record_discovery_started!(
            company: @company,
            conversation: @conversation
          )
          Whatsapp::ProfilingHandler.new(employee: @employee, conversation: @conversation, client: @client).start!
        else
          @conversation.update!(status: "discovery", started_at: Time.current)
          Subscriptions::ConversationLimitEnforcer.record_discovery_started!(
            company: @company,
            conversation: @conversation
          )
          Discovery::ProactiveStartService.call(
            conversation: @conversation,
            employee: @employee,
            client: @client,
            trigger_message_id: external_id,
            delivery_channel: delivery_channel
          )
        end
      else
        send_text("Please reply YES to continue or STOP to opt out.")
      end
    end

    def handle_post_verification(text)
      lang = @employee.preferred_language.presence || LanguageDetector.detect(text)
      @employee.update!(preferred_language: lang) if @employee.preferred_language.blank?

      if Whatsapp::ProfilingHandler.enabled?(@company) && !@employee.profile_complete? && !@conversation.discovery?
        handler = Whatsapp::ProfilingHandler.new(employee: @employee, conversation: @conversation, client: @client)
        @conversation.profiling? ? handler.handle_inbound_text(text) : handler.start!
        return
      end

      @conversation.update!(status: "discovery") unless @conversation.discovery?

      Whatsapp::DiscoveryHandler.new(employee: @employee, conversation: @conversation, client: @client)
                                 .handle_inbound_text(text)
    end

    def send_consent_message
      consent = active_consent
      send_text(consent.body)
    end

    def consent_already_sent?
      consent = active_consent
      @conversation.messages.where(direction: "outbound", channel: @channel).exists?(body: consent.body)
    end

    def active_consent
      ConsentTextVersion.active_for(locale).first ||
        ConsentTextVersion.active_for("en").first ||
        ConsentTextVersion.find_by(active: true)
    end

    def consent_confirmed?(text, consent)
      normalized = text.upcase.strip.gsub(/[ÍÌÎÏ]/, "I")
      keywords = consent.confirmation_keywords.map { |k| k.upcase.gsub(/[ÍÌÎÏ]/, "I") }
      return true if keywords.include?(normalized)

      ConsentTextVersion.where(active: true).find_each do |version|
        version_keywords = version.confirmation_keywords.map { |k| k.upcase.gsub(/[ÍÌÎÏ]/, "I") }
        return true if version_keywords.include?(normalized)
      end

      %w[SI YES I\ AGREE OUI JA].include?(normalized)
    end

    def detect_and_set_language(text)
      return if @employee.preferred_language.present?

      @employee.update!(preferred_language: LanguageDetector.detect(text))
    end

    def greeting_for_unknown_step
      "Hi! I'm the workflow discovery assistant for #{@company.display_name || @company.name}. What's your name?"
    end

    def name_prompt_pending?
      !@conversation.state_snapshot["onboarding_name_prompt_sent"]
    end

    def mark_name_prompt_sent!
      @conversation.update!(
        state_snapshot: @conversation.state_snapshot.merge("onboarding_name_prompt_sent" => true)
      )
    end

    def opt_out_message
      "You've been unsubscribed. Reply anytime if your admin sends a new invitation."
    end

    def locale
      @employee.preferred_language.presence || @company.locale
    end

    def send_text(body)
      persist_message(direction: "outbound", body: body)
      if @client.configured?
        @client.send_text(to: @employee.phone_e164, body: body)
      else
        Rails.logger.info("[WhatsApp dev] to=#{@employee.phone_e164} body=#{body}")
      end
    end

    def persist_message(direction:, body:, external_id: nil)
      Message.create!(
        conversation: @conversation,
        direction: direction,
        channel: @channel,
        message_type: "text",
        body: body,
        external_id: external_id,
        is_discovery_question: direction == "outbound" && @employee.onboarding_step == "verified"
      )
    end

    def delivery_channel
      @channel == "web" ? :web : :whatsapp
    end

  end
end
