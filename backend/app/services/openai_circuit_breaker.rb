# frozen_string_literal: true

# Shared Redis flag with the Python agent (`openai:circuit_open` on REDIS_URL DB /0).
# Rails reads the flag and may trip it only for retryable OpenAI/agent outages.
# The agent owns windowed failure counting; Rails resets on a successful turn.
# Fail-open on Redis errors (prefer availability over hard-block).
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
