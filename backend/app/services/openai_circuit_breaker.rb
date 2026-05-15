# frozen_string_literal: true

class OpenaiCircuitBreaker
  KEY = "openai:circuit_open"

  def self.open?
    REDIS.get(KEY) == "1"
  rescue Redis::BaseError
    false
  end

  def self.trip!(ttl: 300)
    REDIS.setex(KEY, ttl, "1")
  rescue Redis::BaseError
    nil
  end

  def self.reset!
    REDIS.del(KEY)
  rescue Redis::BaseError
    nil
  end
end
