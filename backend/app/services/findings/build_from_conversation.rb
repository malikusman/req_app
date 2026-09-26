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

      findings = areas.filter_map do |area|
        friction = filled(slots["friction::#{area}"])
        next unless friction

        upsert(area, friction, filled(slots["how_it_works::#{area}"]), slots["friction_cost::#{area}"])
      end
      flag_repeated_figures(findings)
      findings
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
      # "Ten to fifteen minutes chasing each PO, then two or three days waiting" was
      # recorded as waiting with a ten-minute duration, and the chase — real work,
      # every week — counted for nothing. A wait is days, not minutes: minutes are the
      # person's own time, and the wait is in the words.
      effort_type = "mixed" if effort_type == "waiting" && duration["unit"] == "minutes" && duration["min"].present?

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
        basis: @conversation.status == "completed" ? "discovery" : "discovery_partial",
        single_occupant_role: single_occupant?,
        evidence: evidence(area, friction, how, cost)
      )
      # Hours come from the model (Finding#compute_annual_hours), so a consultant's
      # corrected figures keep deciding them through every rebuild.
      hours = finding.compute_annual_hours
      finding.confidence = confidence(friction, cost, hours)
      finding.save!
      finding
    end

    # One person giving two areas the very same figures is almost always one piece of
    # work named twice — "purchase orders" and "supplier follow-up" were both the
    # 15-a-week PO chase, and counting both doubled its hours. The later one is
    # flagged, not merged: whether it is the same work is the consultant's call, and
    # until they make it the finding stays out of the report (Finding#needs_review?).
    def flag_repeated_figures(findings)
      seen = {}
      findings.each do |finding|
        signature = figures(finding)
        original = signature && seen[signature]
        if original && finding.status == "draft"
          finding.update!(evidence: finding.evidence.merge("possible_duplicate_of" => original.id))
        else
          finding.update!(evidence: finding.evidence.except("possible_duplicate_of")) if finding.evidence.key?("possible_duplicate_of")
          seen[signature] ||= finding if signature
        end
      end
    end

    def figures(finding)
      return nil unless finding.hours?

      [finding.frequency_min, finding.frequency_max, finding.frequency_unit,
       finding.duration_min, finding.duration_max, finding.duration_unit].map { |v| v.is_a?(BigDecimal) ? v.to_f : v }
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
