# frozen_string_literal: true

module Whatsapp
  class OnboardingHandler
    def initialize(employee:, conversation:, client: MetaClient.new)
      @employee = employee
      @company = employee.company
      @conversation = conversation
      @client = client
    end

    def handle_inbound_text(text)
      text = text.to_s.strip
      return handle_opt_out if opt_out?(text)

      mark_started_if_needed
      detect_and_set_language(text)
      @conversation.touch_activity!

      maybe_send_invite_instructions

      case @employee.onboarding_step
      when "awaiting_name"
        handle_name(text)
      when "awaiting_company"
        handle_company(text)
      when "awaiting_company_join_code"
        handle_company_join_code(text)
      when "awaiting_access_code"
        migrate_legacy_access_code_step
      when "awaiting_consent"
        handle_consent(text)
      when "verified"
        handle_post_verification(text)
      else
        send_text(greeting_for_unknown_step)
      end
    end

    def send_welcome_after_self_serve(name:)
      send_text("Thanks, #{name}! Before we begin, I need your consent.")
      @employee.update!(onboarding_step: "awaiting_consent", display_name: name) if @employee.display_name.blank?
      @employee.update!(onboarding_step: "awaiting_consent") if @employee.display_name.present?
      send_consent_message
    end

    private

    def maybe_send_invite_instructions
      return unless @employee.invited_at.present?
      return if @employee.metadata&.dig("invite_instructions_sent_at").present?

      @employee.update!(
        metadata: (@employee.metadata || {}).merge("invite_instructions_sent_at" => Time.current.iso8601)
      )
      @company.ensure_join_code!
      send_text(invite_instructions_body)
    end

    def invite_instructions_body
      <<~MSG.squish
        You're invited to a short WhatsApp discovery interview for #{@company.display_name || @company.name}.
        Share how work really gets done in your role — text, voice notes, and documents are welcome.
        Company code (for colleagues joining on their own): #{@company.join_code}.
        Reply with your name when you're ready to continue.
      MSG
    end

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
      persist_message(direction: "inbound", body: text)
      @employee.update!(display_name: text)

      if @employee.invited_at.present?
        @employee.update!(onboarding_step: "awaiting_consent")
        send_text("Thanks, #{text}! Before we begin, I need your consent.")
        send_consent_message
      else
        @employee.update!(onboarding_step: "awaiting_consent")
        send_text("Thanks, #{text}! Before we begin, I need your consent.")
        send_consent_message
      end
    end

    def handle_company(text)
      persist_message(direction: "inbound", body: text)
      company_match = ::Company.where("LOWER(name) = ? OR LOWER(display_name) = ?",
                                      text.downcase, text.downcase).first
      company_match ||= @company if text.downcase.include?(@company.name.downcase)

      unless company_match && company_match.id == @company.id
        send_text("I couldn't find that company. Reply with your 5-character company code instead.")
        @employee.update!(onboarding_step: "awaiting_company_join_code")
        return
      end

      @employee.update!(onboarding_step: "awaiting_consent")
      send_text("Great. Before we begin, I need your consent.")
      send_consent_message
    end

    def handle_company_join_code(text)
      persist_message(direction: "inbound", body: "[company code redacted]")
      if @company.verify_join_code?(text)
        log_verification(success: true)
        @employee.update!(onboarding_step: "awaiting_consent")
        send_consent_message
      else
        log_verification(success: false, reason: "invalid_company_code")
        increment_security_snapshot
        send_text("That company code isn't valid. Check with your admin and try again.")
      end
    end

    def migrate_legacy_access_code_step
      @employee.update!(onboarding_step: "awaiting_consent")
      send_text("Please continue — reply YES to accept the consent message below, or STOP to opt out.")
      send_consent_message
    end

    def handle_consent(text)
      persist_message(direction: "inbound", body: text)
      consent = active_consent

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
        @conversation.update!(status: "discovery", started_at: Time.current)
        Subscriptions::ConversationLimitEnforcer.record_discovery_started!(
          company: @company,
          conversation: @conversation
        )
        send_text(welcome_after_consent(lang))
      else
        send_text("Please reply YES to continue or STOP to opt out.")
      end
    end

    def handle_post_verification(text)
      lang = @employee.preferred_language.presence || LanguageDetector.detect(text)
      @employee.update!(preferred_language: lang) if @employee.preferred_language.blank?
      @conversation.update!(status: "discovery") unless @conversation.discovery?

      Whatsapp::DiscoveryHandler.new(employee: @employee, conversation: @conversation, client: @client)
                                 .handle_inbound_text(text)
    end

    def send_consent_message
      consent = active_consent
      send_text(consent&.body || "Reply YES to participate in this discovery interview, or STOP to opt out.")
    end

    def active_consent
      ConsentTextVersion.active_for(locale).first ||
        ConsentTextVersion.active_for("en").first ||
        ConsentTextVersion.find_by(active: true)
    end

    def consent_confirmed?(text, consent)
      normalized = text.upcase.strip.gsub(/[ÍÌÎÏ]/, "I")
      return true if %w[YES SI OUI JA].include?(normalized)

      return false unless consent

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

    def welcome_after_consent(lang)
      {
        "en" => "Thank you! Your discovery conversation will begin shortly. Reply with a short description of your role to get started.",
        "es" => "¡Gracias! Tu conversación de descubrimiento comenzará en breve. Responde con una breve descripción de tu rol para empezar.",
        "fr" => "Merci ! Votre conversation de découverte va commencer. Décrivez brièvement votre rôle pour commencer.",
        "de" => "Danke! Ihr Erkennungsgespräch beginnt in Kürze. Beschreiben Sie kurz Ihre Rolle."
      }.fetch(lang, "Thank you! Your discovery conversation will begin shortly.")
    end

    def greeting_for_unknown_step
      "Hi! I'm the workflow discovery assistant for #{@company.display_name || @company.name}. What's your name?"
    end

    def opt_out_message
      "You've been unsubscribed. Reply anytime with your company code if you'd like to join again."
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
        message_type: "text",
        body: body,
        external_id: external_id,
        is_discovery_question: direction == "outbound" && @employee.onboarding_step == "verified"
      )
    end

    def log_verification(success:, reason: nil)
      AccessCodeVerificationAttempt.create!(
        company: @company,
        employee: @employee,
        phone_e164: @employee.phone_e164,
        success: success,
        failure_reason: reason
      )
    end

    def increment_security_snapshot
      count = AccessCodeVerificationAttempt.where(company: @company, success: false)
                                           .where("created_at > ?", 7.days.ago)
                                           .where(employee_id: nil)
                                           .count
      @company.update!(
        security_snapshot: @company.security_snapshot.merge("unrecognized_verification_attempts_7d" => count)
      )
    end
  end
end
