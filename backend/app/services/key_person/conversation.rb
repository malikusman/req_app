# frozen_string_literal: true

module KeyPerson
  # A key person's way into their conversation with leadership, whichever door
  # they come through (the key user's portal, or a manager's link): whether it's
  # available, their current session, consent, and coming back to it.
  class Conversation
    class NotAvailable < StandardError; end

    CONSENT_VERSION = "2026-11-05"
    # Back after this long without a word: welcome them back before carrying on.
    IDLE_RESUME = 30.minutes

    # With the switch off or no model, the conversation isn't offered: a form
    # pretending to be a conversation would be worse than the team arranging it.
    def self.available?(client: Openai::Client.new)
      Llm::KeyPerson.enabled? && client.configured?
    end

    def initialize(participant, client: Openai::Client.new)
      @participant = participant
      @client = client
    end

    def session = @participant.conversation_sessions.last

    # Consent (Doc 14 §5), then the opening. Coming back to a session that has
    # already started does nothing new; a finished one is left as it is.
    def start!
      raise NotAvailable unless self.class.available?(client: @client)

      current = @participant.with_lock do
        existing = session
        next existing if existing && existing.state != "NOT_STARTED"

        @participant.update!(consent_recorded_at: Time.current, consent_text_version: CONSENT_VERSION,
                             participation_status: "STARTED")
        existing ||= @participant.conversation_sessions.create!(
          company: @participant.company, engagement: @participant.engagement, version: 1,
          language: first_language, limits: Planner.limits_for(@participant.company)
        )
        existing.move_to("CONSENT")
        existing.update!(started_at: Time.current, last_activity_at: Time.current)
        existing
      end
      Turn.new(current, client: @client).open! if current.state == "CONSENT"
      current.reload
    end

    def needs_resume?(current = session)
      return false if current.nil? || current.finished? || %w[NOT_STARTED CONSENT].include?(current.state)

      current.paused? || current.last_activity_at.nil? || current.last_activity_at < IDLE_RESUME.ago
    end

    def resume!
      raise NotAvailable unless self.class.available?(client: @client)

      current = session
      Turn.new(current, client: @client).resume! if needs_resume?(current)
      current.reload
    end

    private

    def first_language
      @participant.preferred_language.to_s.start_with?("ar") ? "ar" : "en"
    end
  end
end
