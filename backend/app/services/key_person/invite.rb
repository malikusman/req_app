# frozen_string_literal: true

module KeyPerson
  # Asks a key person to their conversation with leadership (Doc 14 §4).
  #
  # The key user already signs in to the portal, so they get an email saying
  # their conversation is ready there. Another manager gets a signed link of
  # their own: no password, no app, and it works on a phone (Doc 14 §4.3). Only
  # a digest of the link is stored; inviting again (a reminder, a resend) issues
  # a fresh link, and the old one stops working.
  #
  # Email is the invitation. A WhatsApp template is sent as well once one has
  # been approved for it (META_TEMPLATE_KEY_PERSON_INVITE); the inbound WhatsApp
  # handler doesn't know key persons, so the message asks them to tap the link
  # rather than reply.
  class Invite
    LINK_TTL = 14.days

    def self.call(participant)
      new(participant).call
    end

    def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

    # The participant a link belongs to, while it is valid and their engagement
    # is still open.
    def self.participant_for(token)
      return nil if token.blank?

      participant = EngagementParticipant.key_persons.planned.find_by(access_token_digest: digest(token))
      return nil unless participant
      return nil if participant.access_token_expires_at.nil? || participant.access_token_expires_at.past?
      return nil if participant.engagement.closed?

      participant
    end

    def initialize(participant)
      @participant = participant
    end

    def call
      return false if @participant.email.blank? && !@participant.key_user?

      if @participant.key_user?
        KeyPersonMailer.ready(@participant).deliver_later
      else
        url = link!
        KeyPersonMailer.invitation(@participant, url).deliver_later
        send_whatsapp(url)
      end
      status = @participant.participation_status == "NOT_INVITED" ? "INVITED" : @participant.participation_status
      @participant.update!(invited_at: Time.current, participation_status: status,
                           persona: @participant.persona || Personas.from_title(@participant.role_title))
      true
    end

    # Where this person's conversation is: the portal for the key user; for a
    # manager, a fresh signed link, which replaces the one before.
    def link!
      return "#{NotificationService.app_host}/company/leadership" if @participant.key_user?

      token = SecureRandom.urlsafe_base64(32)
      @participant.update!(access_token_digest: self.class.digest(token), access_token_expires_at: LINK_TTL.from_now)
      "#{NotificationService.app_host}/leadership/#{token}"
    end

    private

    def send_whatsapp(url)
      template = ENV["META_TEMPLATE_KEY_PERSON_INVITE"].presence
      return if template.blank? || @participant.phone_e164.blank?

      client = Whatsapp::MetaClient.new
      return unless client.configured?

      company = @participant.company
      client.send_template(
        to: @participant.phone_e164, template_name: template,
        language_code: @participant.preferred_language.presence || "en",
        components: [{ type: "body", parameters: [{ type: "text", text: @participant.name },
                                                  { type: "text", text: company.display_name.presence || company.name },
                                                  { type: "text", text: url }] }]
      )
    rescue StandardError => e
      Rails.logger.warn("[KeyPerson::Invite] WhatsApp invitation not sent to participant #{@participant.id}: #{e.message}")
    end
  end
end
