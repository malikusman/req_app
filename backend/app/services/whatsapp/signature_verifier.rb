# frozen_string_literal: true

module Whatsapp
  class SignatureVerifier
    def self.valid?(payload, signature_header)
      secret = ENV["META_APP_SECRET"]
      return true if secret.blank? && Rails.env.development?

      return false if signature_header.blank?

      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature_header)
    end
  end
end
