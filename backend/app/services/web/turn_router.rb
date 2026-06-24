# frozen_string_literal: true

module Web
  class TurnRouter
    CHANNEL = "web"

    def self.bootstrap!(employee:, conversation:)
      client = CapturingMetaClient.new

      if employee.onboarding_step == "awaiting_consent"
        Whatsapp::OnboardingHandler.new(
          employee: employee,
          conversation: conversation,
          client: client,
          channel: CHANNEL
        ).prompt_consent_if_needed!
      elsif should_start_profiling?(employee, conversation)
        Whatsapp::ProfilingHandler.new(
          employee: employee,
          conversation: conversation,
          client: client,
          channel: CHANNEL
        ).start!
      end

      client.sent_messages
    end

    def self.handle_text(employee:, conversation:, text:)
      text = text.to_s.strip
      return { employee: employee, conversation: conversation } if text.blank?

      client = CapturingMetaClient.new

      if conversation.profiling?
        Whatsapp::ProfilingHandler.new(
          employee: employee,
          conversation: conversation,
          client: client,
          channel: CHANNEL
        ).handle_inbound_text(text)
      elsif conversation.discovery? || employee.onboarding_step == "verified"
        Whatsapp::DiscoveryHandler.new(
          employee: employee,
          conversation: conversation,
          client: client,
          channel: CHANNEL
        ).handle_inbound_text(text)
      else
        Whatsapp::OnboardingHandler.new(
          employee: employee,
          conversation: conversation,
          client: client,
          channel: CHANNEL
        ).handle_inbound_text(text)
      end

      { employee: employee.reload, conversation: conversation.reload }
    end

    def self.should_start_profiling?(employee, conversation)
      return false unless employee.onboarding_step == "verified"
      return false unless Whatsapp::ProfilingHandler.enabled?(employee.company)
      return false if employee.profile_complete?
      return false unless conversation.profiling?
      return false if conversation.messages.where(direction: "outbound").exists?

      true
    end

    private_class_method :should_start_profiling?
  end
end
