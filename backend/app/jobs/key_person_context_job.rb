# frozen_string_literal: true

# Builds a finished conversation's management context, findings and planned
# initiatives (P04) in the background, so the participant's closing turn never
# waits on it. Safe to run twice: a session gets one context.
class KeyPersonContextJob < ApplicationJob
  queue_as :default

  def perform(session_id)
    session = ConversationSession.find_by(id: session_id)
    KeyPerson::ContextBuilder.call(session) if session&.finished?
  end
end
