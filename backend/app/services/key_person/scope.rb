# frozen_string_literal: true

module KeyPerson
  # The scope card: near the end of the key user's conversation, they confirm
  # which departments take part, settle how many people from each, and confirm
  # the people they mentioned (Doc 08 §13). This is where counts left as "Not
  # sure" at onboarding become numbers before Stage 1 is priced (Doc 07 §10).
  #
  # Only the key user's own conversation has a scope card: they own the plan.
  # People other managers mention go to the consultant instead.
  class Scope
    class Locked < StandardError; end

    def initialize(session)
      @session = session
      @engagement = session.engagement
    end

    def editable? = @engagement.status == "KEY_PERSON_DISCOVERY"

    def json
      {
        editable: editable?,
        departments: Array(@engagement.planned_departments),
        counts_known: !@engagement.planned_participant_count.nil?,
        suggested_departments: suggested_departments,
        people_mentioned: proposals.each_with_index.filter_map do |person, index|
          next if person["confirmed_id"] || person["dismissed"]

          person.slice("name", "role", "department", "reason").merge("index" => index)
        end,
        planned_people: @engagement.participants.planned.order(:created_at).map do |p|
          { id: p.id, name: p.name, participant_type: p.participant_type, department: p.department,
            role_title: p.role_title }
        end
      }
    end

    # Returns the people left in a department that is no longer taking part.
    def update_departments!(rows)
      raise Locked unless editable?

      planned = Engagements::PlannedDepartments.normalise(rows)
      raise ArgumentError, "Choose at least one department to take part" if planned.empty?

      @engagement.update!(planned_departments: planned)
      Completion.hand_over_to_pricing(@engagement, actor: @session.participant.company_user)
      Engagements::PlannedDepartments.stranded_people(@engagement, planned)
    end

    # Someone the key user mentioned, confirmed with their details. A manager is
    # invited straight away; staff are invited later, after Stage 1 is agreed.
    def confirm_person!(index, attrs)
      raise Locked unless editable?

      @session.with_lock do
        person = proposals.fetch(Integer(index)) { raise ActiveRecord::RecordNotFound }
        participant = @engagement.participants.create!(
          attrs.merge(company: @engagement.company, source: "KEY_PERSON_CONVERSATION", nominated_by_client: true)
        )
        mark!(index, "confirmed_id" => participant.id)
        Invite.call(participant) if participant.participant_type == "KEY_PERSON" && participant.email.present?
        participant
      end
    end

    def dismiss_person!(index)
      @session.with_lock do
        proposals.fetch(Integer(index)) { raise ActiveRecord::RecordNotFound }
        mark!(index, "dismissed" => true)
      end
    end

    private

    def proposals = Array(@session.reload.state_snapshot["participants_mentioned"])

    def mark!(index, attrs)
      snapshot = @session.state_snapshot.deep_dup
      snapshot["participants_mentioned"][Integer(index)].merge!(attrs)
      @session.update!(state_snapshot: snapshot)
    end

    def suggested_departments
      profile = Array(@engagement.company.company_profile&.dig("org_departments"))
      (Array(@engagement.departments_in_scope) + profile + Array(@engagement.planned_departments).pluck("name"))
        .map(&:to_s).reject(&:blank?).uniq(&:downcase)
    end
  end
end
