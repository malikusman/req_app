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

    def self.handle_media(employee:, conversation:, file:, caption: nil)
      Web::MediaInboundService.call(
        employee: employee,
        conversation: conversation,
        file: file,
        caption: caption
      )
    end

    # Shares Inbound::TrackRouter with the WhatsApp channel. Before that, this method
    # went straight to profiling/discovery/onboarding and never checked for an open
    # consultant question — so an employee answering one here had their reply
    # swallowed by the discovery handler and the consultant was never notified.
    def self.handle_text(employee:, conversation:, text:)
      text = text.to_s.strip
      return { employee: employee, conversation: conversation } if text.blank?

      Inbound::TrackRouter.call(
        employee: employee,
        conversation: conversation,
        text: text,
        channel: CHANNEL,
        client: CapturingMetaClient.new
      )

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
