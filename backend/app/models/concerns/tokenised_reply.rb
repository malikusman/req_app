# frozen_string_literal: true

# A single-use-ish reply link for something we asked someone outside the app.
#
# Only the digest is stored, so the raw token exists exactly once — in the email we
# send. A leaked database gives an attacker nothing to replay.
#
# Shared by ConsultantOutreach (admin-gated clarifications) and
# ConsultantInfoRequest (direct consultant follow-ups) so the two channels resolve
# tokens the same way and one public endpoint can serve both.
module TokenisedReply
  extend ActiveSupport::Concern

  class_methods do
    def find_by_reply_token(raw_token)
      return nil if raw_token.blank?

      find_by(reply_token_digest: TokenisedReply.digest(raw_token))
    end
  end

  # Returns the raw token — the only time it exists in plaintext. Store nothing
  # but the digest.
  def mint_reply_token!
    raw = SecureRandom.urlsafe_base64(32)
    update!(reply_token_digest: TokenisedReply.digest(raw))
    raw
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end
end
