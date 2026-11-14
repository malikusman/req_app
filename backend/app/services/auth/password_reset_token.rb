# frozen_string_literal: true

# Signed, expiring tokens for set-password / forgot-password (FEAT-SIGNUP).
module Auth
  class PasswordResetToken
    PURPOSE = :password_reset
    TTL = 48.hours
    # A first invitation may sit in an inbox for days before the key user opens it.
    INVITATION_TTL = 7.days

    def self.generate(record, ttl: TTL)
      verifier.generate(
        { "type" => record.class.name, "id" => record.id },
        expires_in: ttl,
        purpose: PURPOSE
      )
    end

    def self.verify(token)
      payload = verifier.verify(token.to_s, purpose: PURPOSE)
      payload.fetch("type").constantize.find_by(id: payload.fetch("id"))
    rescue ActiveSupport::MessageVerifier::InvalidSignature, KeyError, NameError
      nil
    end

    def self.verifier
      Rails.application.message_verifier("auth/password_reset")
    end
  end
end
