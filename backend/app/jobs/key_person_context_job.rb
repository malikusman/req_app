# frozen_string_literal: true

# Builds a finished conversation's management context, findings and planned
# initiatives (P04) in the background, so the participant's closing turn never
# waits on it. Safe to run twice: a session gets one context.
class KeyPersonContextJob < ApplicationJob
  queue_as :default

  def perform(session_id)
    session = ConversationSession.find_by(id: session_id)
    return unless session&.finished?

    KeyPerson::ContextBuilder.call(session)
    # A new leadership context is new evidence for synthesis (Doc 08 §19).
    SynthesisRunJob.request(session.engagement, trigger: "LEADERSHIP")
  end
end
