# frozen_string_literal: true

module KeyPerson
  # Reminders for the conversations with leadership (Doc 14 §9.1), sent only in
  # the company's working hours:
  #
  #   - not started: two working days after the invitation, then four; then
  #     stop — the key user sees "not started" and can chase it themselves;
  #   - paused: one working day after they last said anything, once per pause;
  #   - documents asked for and not received: once, two working days later.
  #
  # A manager's link is refreshed with each reminder (Doc 14 §4.3). By email:
  # the WhatsApp side doesn't handle replies from key persons.
  class Reminders
    NOT_STARTED_AFTER = [2, 4].freeze
    PAUSED_AFTER = 1
    DOCUMENTS_AFTER = 2

    def self.run(at: Time.current)
      new(at).run
    end

    def initialize(at)
      @at = at
    end

    def run
      EngagementParticipant.key_persons.joins(:engagement)
                           .where(engagements: { status: %w[KEY_PERSON_DISCOVERY STAGE_1_PRICING] })
                           .where(participation_status: %w[INVITED STARTED PAUSED])
                           .includes(:company).find_each do |participant|
        next unless WorkingTime.open?(participant.company, at: @at)

        remind_to_start(participant) || remind_to_resume(participant)
        remind_about_documents(participant)
      end
    end

    private

    def remind_to_start(participant)
      return false unless participant.participation_status == "INVITED"

      due = NOT_STARTED_AFTER[participant.reminder_count]
      return false unless due
      return false if working_days(participant.invited_at, participant) < due

      send!(participant, participant.reminder_count.zero? ? "not_started" : "not_started_again")
    end

    def remind_to_resume(participant)
      session = participant.conversation_sessions.last
      return false unless session&.paused?
      return false if participant.last_reminded_at && participant.last_reminded_at > session.last_activity_at
      return false if working_days(session.last_activity_at, participant) < PAUSED_AFTER

      send!(participant, "paused")
    end

    def remind_about_documents(participant)
      session = participant.conversation_sessions.last
      return unless session

      open = DocumentRequest.open.where(conversation_session_id: session.id, reminded_at: nil)
                            .select { |r| working_days(r.created_at, participant) >= DOCUMENTS_AFTER }
      return if open.empty?

      KeyPersonMailer.reminder(participant, Invite.new(participant).link!, "documents",
                               documents: open.map(&:requested_item)).deliver_later
      DocumentRequest.where(id: open.map(&:id)).update_all(reminded_at: @at) # rubocop:disable Rails/SkipsModelValidations
    end

    def send!(participant, kind)
      KeyPersonMailer.reminder(participant, Invite.new(participant).link!, kind).deliver_later
      participant.update!(reminder_count: participant.reminder_count + 1, last_reminded_at: @at)
      true
    end

    def working_days(from, participant)
      from ? WorkingTime.working_days_between(from, @at, participant.company) : 0
    end
  end
end
