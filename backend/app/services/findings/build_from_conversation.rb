# frozen_string_literal: true

module Findings
  # Turns one interview's dossier into findings: one per role area where the
  # employee described what snags, carrying how the work happens, how often, how
  # long, and the hours that implies.
  #
  # Runs when an interview completes, and when one is abandoned — an employee who
  # answered six questions and drifted away still told us something real, and
  # throwing it away (as the signal layer does) loses evidence. Those findings are
  # marked discovery_partial and carry lower confidence.
  #
  # Idempotent: re-running for the same interview (after an addendum, say) updates
  # the machine-derived fields in place. A consultant's decision — approve, hide,
  # merge — is never overwritten by a rebuild.
  class BuildFromConversation
    THRESHOLD = 0.6
    BUILDABLE = %w[completed abandoned].freeze

    def self.call(conversation:)
      new(conversation: conversation).call
    end

    def initialize(conversation:)
      @conversation = conversation
      @employee = conversation.employee
      @company = conversation.company
    end

    def call
      return [] unless BUILDABLE.include?(@conversation.status)

      blackboard = @conversation.blackboard
      slots = (blackboard["dossier"] || {})["slots"] || {}
      areas = Array(blackboard["role_areas"]).filter_map { |a| a["name"].presence }

      areas.filter_map do |area|
        friction = filled(slots["friction::#{area}"])
        next unless friction

        upsert(area, friction, filled(slots["how_it_works::#{area}"]), slots["friction_cost::#{area}"])
      end
    end

    private

    def filled(entry)
      return nil unless entry.is_a?(Hash) && entry["value"].present?

      entry["confidence"].to_f >= THRESHOLD ? entry : nil
    end

    def upsert(area, friction, how, cost)
      effort = (cost || {})["effort"] || {}
      frequency = effort["frequency"] || {}
      duration = effort["duration"] || {}
      effort_type = Finding::EFFORT_TYPES.include?(effort["effort_type"]) ? effort["effort_type"] : "unknown"

      hours = AnnualHours.call(
        frequency_min: frequency["min"], frequency_max: frequency["max"], frequency_unit: frequency["unit"],
        duration_min: duration["min"], duration_max: duration["max"], duration_unit: duration["unit"],
        effort_type: effort_type
      )

      finding = @company.findings.find_or_initialize_by(source_key: source_key(area))
      finding.assign_attributes(
        employee: @employee,
        conversation: @conversation,
        department: @employee&.department,
        role_title: @employee&.role_title,
        area: area.to_s.truncate(120),
        what_happens_now: how&.dig("value"),
        friction: friction["value"],
        frequency_as_said: frequency["as_said"]&.truncate(250),
        frequency_min: frequency["min"],
        frequency_max: frequency["max"],
        frequency_unit: Finding::FREQUENCY_UNITS.include?(frequency["unit"]) ? frequency["unit"] : nil,
        duration_as_said: duration["as_said"]&.truncate(250),
        duration_min: duration["min"],
        duration_max: duration["max"],
        duration_unit: Finding::DURATION_UNITS.include?(duration["unit"]) ? duration["unit"] : nil,
        effort_type: effort_type,
        annual_hours_min: hours.min,
        annual_hours_max: hours.max,
        hours_basis: hours.basis.merge("reason" => hours.reason).compact,
        basis: @conversation.status == "completed" ? "discovery" : "discovery_partial",
        confidence: confidence(friction, cost, hours),
        single_occupant_role: single_occupant?,
        evidence: evidence(area, friction, how, cost)
      )
      finding.save!
      finding
    end

    def source_key(area)
      "conversation:#{@conversation.id}:#{area.to_s.downcase.squish}"
    end

    def confidence(friction, cost, hours)
      return "low" if @conversation.status != "completed"
      return "low" if friction["accepted_after_retry"] || cost&.dig("accepted_after_retry")
      return "high" if hours.hours? && friction["confidence"].to_f >= 0.8

      "medium"
    end

    # With one person in a role, a finding about the role is a finding about them.
    def single_occupant?
      title = @employee&.role_title.to_s.strip.downcase
      return false if title.blank?

      @company.employees.where("LOWER(TRIM(role_title)) = ?", title).count <= 1
    end

    def evidence(area, friction, how, cost)
      {
        "conversation_id" => @conversation.id,
        "slots" => {
          "friction" => friction["turn"],
          "how_it_works" => how&.dig("turn"),
          "friction_cost" => cost&.dig("turn")
        }.compact,
        "area" => area
      }
    end
  end
end
