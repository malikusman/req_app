# frozen_string_literal: true

# Starts the conversations with leadership once onboarding has been handed over
# (KeyPerson::Kickoff). Run after the hand-over commits, so it sees it.
class KeyPersonKickoffJob < ApplicationJob
  queue_as :default

  def perform(engagement_id)
    engagement = Engagement.find_by(id: engagement_id)
    KeyPerson::Kickoff.call(engagement) if engagement
  end
end
