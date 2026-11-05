# frozen_string_literal: true

module KeyPerson
  # A conversation with leadership has finished. The participant is marked done,
  # their context is built in the background (P04), the lead consultant is told,
  # and — when it was the key user's conversation and every planned count is a
  # number — the engagement moves on to Stage 1 pricing (Doc 08 §13, Doc 17 §1).
  class Completion
    def self.call(session)
      new(session).call
    end

    # Tried again whenever the counts are settled later (the scope card, a
    # consultant). Quietly does nothing until everything pricing needs is there.
    def self.hand_over_to_pricing(engagement, actor: nil)
      return false unless engagement.status == "KEY_PERSON_DISCOVERY"

      Engagements::Transition.call(engagement: engagement, to: "STAGE_1_PRICING", actor: actor)
      true
    rescue Engagements::Transition::Error => e
      Rails.logger.info("[KeyPerson::Completion] engagement #{engagement.id} stays in leadership conversations: #{e.message}")
      false
    end

    def initialize(session)
      @session = session
      @participant = session.participant
    end

    def call
      @participant.update!(participation_status: "COMPLETED") if @session.state == "COMPLETE"
      notify_consultant
      self.class.hand_over_to_pricing(@session.engagement, actor: @participant.company_user) if @participant.key_user?
    end

    private

    def notify_consultant
      consultant = @session.engagement.lead_consultant
      return unless consultant

      company = @session.company
      NotificationService.notify(
        type: :key_person_completed, company: company, recipients: consultant,
        title: "Leadership conversation finished",
        body: "#{@participant.name} (#{company.display_name.presence || company.name}) has finished their conversation.",
        action_url: "#{NotificationService.app_host}/consultant/companies/#{company.id}",
        metadata: { conversation_session_id: @session.id, close_reason: @session.close_reason }
      )
    end
  end
end
