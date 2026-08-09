# frozen_string_literal: true

module Companion
  # Stores companion notes on conversation.state_snapshot (no report feed until promote).
  class NoteStore
    KEY = "companion"

    def self.companion_state(conversation)
      snapshot = conversation.state_snapshot.is_a?(Hash) ? conversation.state_snapshot : {}
      (snapshot[KEY].is_a?(Hash) ? snapshot[KEY] : {}).deep_dup
    end

    def self.awaiting_promote_confirm?(conversation)
      companion_state(conversation)["awaiting_promote_confirm"] == true
    end

    def self.append_note!(conversation:, body:, intent:)
      state = companion_state(conversation)
      notes = Array(state["notes"])
      notes << {
        "body" => body.to_s.truncate(2000),
        "intent" => intent.to_s,
        "at" => Time.current.iso8601
      }
      state["notes"] = notes.last(50)
      write!(conversation, state)
      state
    end

    def self.mark_awaiting_promote!(conversation:, pending_body:)
      state = companion_state(conversation)
      state["awaiting_promote_confirm"] = true
      state["pending_note"] = pending_body.to_s.truncate(2000)
      write!(conversation, state)
      state
    end

    def self.clear_awaiting_promote!(conversation)
      state = companion_state(conversation)
      pending = state.delete("pending_note")
      state["awaiting_promote_confirm"] = false
      write!(conversation, state)
      pending
    end

    def self.write!(conversation, companion_state)
      snapshot = conversation.state_snapshot.is_a?(Hash) ? conversation.state_snapshot.deep_dup : {}
      snapshot[KEY] = companion_state
      conversation.update!(state_snapshot: snapshot, last_activity_at: Time.current)
    end
    private_class_method :write!
  end
end
