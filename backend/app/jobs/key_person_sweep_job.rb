# frozen_string_literal: true

# Hourly: a conversation with leadership left for two hours counts as paused,
# so the paused reminder can follow; then the reminders due now are sent.
class KeyPersonSweepJob < ApplicationJob
  queue_as :default

  IDLE_AFTER = 2.hours

  def perform
    ConversationSession.key_person
                       .where.not(state: ConversationSession::FINISHED_STATES + %w[NOT_STARTED CONSENT PAUSED])
                       .where(last_activity_at: ...IDLE_AFTER.ago)
                       .find_each { |session| KeyPerson::Turn.new(session).mark_idle! }
    KeyPerson::Reminders.run
  end
end
