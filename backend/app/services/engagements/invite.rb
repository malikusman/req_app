# frozen_string_literal: true

module Engagements
  # Invites the key user to their engagement (Doc 07 §3): a set-password link by
  # email, and a WhatsApp message once a template for it has been approved.
  # Sending again issues a fresh link; earlier links still work until they expire.
  class Invite
    def self.call(engagement:)
      new(engagement: engagement).call
    end

    def initialize(engagement:)
      @engagement = engagement
      @key_user = engagement.key_user
    end

    def call
      return false unless @key_user

      token = Auth::PasswordResetToken.generate(@key_user, ttl: Auth::PasswordResetToken::INVITATION_TTL)
      SignupMailer.engagement_invitation(@engagement, token).deliver_later
      send_whatsapp
      true
    end

    private

    # Doc 14 §4.2: anything Mjadi starts on WhatsApp needs a pre-approved template.
    # Until one exists for key users, the email is the invitation.
    def send_whatsapp
      template = ENV["META_TEMPLATE_KEY_USER_INVITE"].presence
      return if template.blank? || @key_user.phone.blank?

      client = Whatsapp::MetaClient.new
      return unless client.configured?

      company_name = @engagement.company.display_name.presence || @engagement.company.name
      client.send_template(
        to: @key_user.phone,
        template_name: template,
        language_code: @engagement.languages.first.presence || "en",
        components: [{ type: "body", parameters: [{ type: "text", text: @key_user.name },
                                                  { type: "text", text: company_name }] }]
      )
    rescue StandardError => e
      Rails.logger.warn("[Engagements::Invite] WhatsApp invitation not sent for engagement #{@engagement.id}: #{e.message}")
    end
  end
end
