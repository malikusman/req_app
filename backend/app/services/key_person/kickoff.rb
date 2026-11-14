# frozen_string_literal: true

module KeyPerson
  # Onboarding has been handed over: the conversations with leadership begin
  # (Doc 07 §12.5–6). The key user gets a participant row of their own and word
  # that their conversation is ready; each other manager the key user named, who
  # has an email address, is invited. Safe to run again: anyone already invited
  # is left alone.
  class Kickoff
    def self.call(engagement)
      new(engagement).call
    end

    def initialize(engagement)
      @engagement = engagement
      @key_user = engagement.key_user
    end

    def call
      return unless @engagement.status == "KEY_PERSON_DISCOVERY" && @key_user

      own = key_user_participant!
      Invite.call(own) if own.participation_status == "NOT_INVITED"
      @engagement.participants.planned.key_persons.where(participation_status: "NOT_INVITED").find_each do |manager|
        Invite.call(manager) if manager.email.present?
      end
    end

    private

    # If the key user also put themselves on the list of managers, that row
    # becomes theirs, so they aren't invited twice.
    def key_user_participant!
      EngagementParticipant.transaction do
        own = @engagement.participants.find_by(source: "KEY_USER")
        own ||= @engagement.participants.key_persons.where("LOWER(email) = ?", @key_user.email.to_s.downcase).first
        own ||= @engagement.participants.new(company: @engagement.company, participant_type: "KEY_PERSON")
        own.update!(
          source: "KEY_USER", company_user: @key_user, name: @key_user.name, email: @key_user.email,
          role_title: own.role_title.presence || @key_user.job_title,
          persona: own.persona || Personas.from_title(@key_user.job_title),
          preferred_language: @key_user.preferred_language.presence || own.preferred_language,
          scope: own.scope.presence || scope_for(@key_user.job_title)
        )
        own
      end
    end

    def scope_for(title)
      return "Company-wide" if Personas.company_wide?(Personas.from_title(title))
      return nil if @engagement.scope_type != "DEPARTMENT"

      Array(@engagement.departments_in_scope).join(", ").presence
    end
  end
end
