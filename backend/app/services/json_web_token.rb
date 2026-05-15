# frozen_string_literal: true

class JsonWebToken
  class << self
    def encode(payload, expires_at: nil)
      payload = payload.dup
      expires_at ||= 24.hours.from_now
      payload[:exp] = expires_at.to_i
      JWT.encode(payload, secret, "HS256")
    end

    def decode(token)
      body = JWT.decode(token, secret, true, algorithm: "HS256").first
      ActiveSupport::HashWithIndifferentAccess.new(body)
    rescue JWT::DecodeError
      nil
    end

    def secret
      ENV.fetch("JWT_SECRET") { Rails.application.secret_key_base }
    end
  end
end
