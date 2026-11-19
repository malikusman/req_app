# frozen_string_literal: true

module Discovery
  # Redis makes activity visible while the database transaction holds the turn lock.
  class TurnStatus
    def self.key(message)
      "discovery:processing:#{message.id}"
    end

    def self.processing?(message)
      message && REDIS.get(key(message)) == "1"
    rescue Redis::BaseError
      false
    end

    def self.track(message)
      begin
        REDIS.setex(key(message), Langgraph::Client::READ_TIMEOUT + 30, "1")
      rescue Redis::BaseError
        # Processing must still work if status reporting is unavailable.
      end
      yield
    ensure
      begin
        REDIS.del(key(message))
      rescue Redis::BaseError
        nil
      end
    end
  end
end
