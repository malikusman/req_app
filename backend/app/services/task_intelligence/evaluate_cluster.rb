# frozen_string_literal: true

module TaskIntelligence
  class EvaluateCluster
    OBJECTIVES = {
      "steps_decisions" => "Reconstruct the current steps and decisions.",
      "trigger_inputs" => "Confirm the trigger and inputs.",
      "output_recipient" => "Confirm the output and who receives it.",
      "frequency_volume" => "Establish volume and frequency for this process.",
      "active_effort" => "Measure active effort per instance separately from waiting.",
      "tools" => "Identify the systems used at each step.",
      "dependencies" => "Identify owners, approvals and handoffs.",
      "exceptions" => "Investigate exceptions, controls and how failures are handled."
    }.freeze
    FIELDS = (OBJECTIVES.keys + ["bottlenecks"]).freeze
    CORE = %w[steps_decisions trigger_inputs output_recipient].freeze
    GOAL_STOP_WORDS = %w[about across improve increase reduce process processes business company operations].freeze

    def initialize(revision:, memberships:, evidence_conversations:, overlaps:, goals:)
      @revision = revision
      @memberships = memberships
      @overlaps = overlaps
      @goals = goals
      @clarifications = revision.relationships.filter_map { |relationship| relationship["clarification_request"] }
                                .select { |request| request["status"] == "open" }.uniq { |request| request["id"] }
      @sources = memberships.map(&:task_source)
      @evidence = @sources.to_h do |source|
        [source.id, ProcessClusters::SourceEvidence.new(source, evidence_conversations)]
      end
      @finding_links = @sources.filter_map do |source|
        finding = source.finding
        next unless finding && finding.company_id == source.company_id && finding.conversation_id == source.conversation_id &&
                    finding.employee_id == source.employee_id && finding.status.in?(%w[draft approved])

        { "id" => finding.id, "task_source_id" => source.id, "status" => finding.status, "confidence" => finding.confidence }
      end
    end

    def call
      sources = source_coverage
      known = sources.flat_map { |source| source.fetch("reported_fields") }.uniq
      conflicts = sources.flat_map { |source| source.fetch("conflicting_fields") }.uniq
      workload = process_workload
      release = possible_release(conflicts, workload)
      frequency = reported_frequency
      risks = risk_signals(known, conflicts)
      objectives = objectives_for(known, conflicts, workload, frequency)
      confidence = confidence_for(sources, conflicts)
      grounded = known.intersect?(%w[steps_decisions bottlenecks exceptions dependencies]) || conflicts.any?
      scores = scoring(known, workload, release, frequency, risks, objectives, confidence, grounded)
      score = scores.values.sum
      focus = primary_focus(scores)

      {
        process_cluster_revision_id: @revision.id,
        title: @sources.first.name, score: score,
        priority: score >= 13 ? "high" : (score >= 8 ? "medium" : "low"),
        confidence: confidence,
        assessment: {
          "basis" => "deterministic_evaluation_of_reported_evidence",
          "grounded_for_investigation" => grounded && objectives.any?,
          "focus" => focus,
          "score_breakdown" => scores,
          "evidence_sources" => sources,
          "findings" => @finding_links,
          "observed_workload" => workload,
          "possible_released_effort" => release,
          "highest_reported_annual_frequency" => frequency,
          "risks" => risks,
          "unknowns" => unknowns(known, conflicts, workload, frequency, release),
          "deep_dive_objectives" => objectives,
          "potential_overlap_cluster_ids" => @overlaps,
          "clarification_requests" => @clarifications,
          "investigation_scope" => @overlaps.any? ? "provisional_overlap_review" : "cluster_observation"
        }
      }
    end

    private

    def source_coverage
      @sources.map do |source|
        evidence = @evidence.fetch(source.id)
        facts = FIELDS.filter_map { |field| field if evidence.fact(field) }
        facts << "steps_decisions" if evidence.legacy_slot("how_it_works")
        facts << "bottlenecks" if evidence.legacy_slot("friction")
        verified = CORE.select { |field| evidence.fact(field)&.dig("evidence", "message_id").present? }
        {
          "task_source_id" => source.id, "source_version" => source.version,
          "reported_fields" => facts.uniq, "message_anchored_core_fields" => verified,
          "conflicting_fields" => FIELDS.select { |field| evidence.fact(field, status: "conflict") }
        }
      end
    end

    def process_workload
      summary = @revision.effort_summary
      return unless summary["status"].in?(%w[independent_observation separate_stages])
      return unless summary["quantified_source_count"] == @sources.size
      return unless @sources.all? { |source| @evidence.fetch(source.id).fact("active_effort") }
      return unless positive_number?(summary["annual_hours_min"]) && positive_number?(summary["annual_hours_max"])
      return if summary["annual_hours_min"] > summary["annual_hours_max"]

      workload = summary.slice("annual_hours_min", "annual_hours_max", "status")
      if @overlaps.any?
        workload.merge!("status" => "unresolved_overlap", "reported_status" => summary.fetch("status"),
                        "cross_cluster_overlap_unresolved" => true)
      else
        workload["cross_cluster_overlap_unresolved"] = false
      end
      workload
    end

    def possible_release(conflicts, workload)
      return unless @sources.one? && @overlaps.empty? && conflicts.empty?
      return unless @revision.effort_summary["status"].in?(%w[independent_observation unknown])
      return unless @evidence.fetch(@sources.first.id).fact("bottlenecks")

      item = @memberships.first.effort_observations.find do |observation|
        observation["scope"] == "bottleneck" && observation["effort_type"] == "active"
      end
      return unless item

      frequency = item.fetch("frequency")
      duration = item.fetch("duration")
      hours = Findings::AnnualHours.call(
        frequency_min: frequency["min"], frequency_max: frequency["max"], frequency_unit: frequency["unit"],
        duration_min: duration["min"], duration_max: duration["max"], duration_unit: duration["unit"],
        effort_type: "active"
      )
      return unless hours.hours? && !hours.basis["capped_at_capacity"]
      return if workload && hours.max > workload.fetch("annual_hours_max")

      {
        "annual_hours_upper_bound" => hours.max, "task_source_id" => @sources.first.id,
        "basis" => "Reported active bottleneck time if fully removed. Validate avoidability and scope before claiming savings.",
        "calculation_basis" => hours.basis
      }
    end

    def reported_frequency
      @memberships.filter_map do |member|
        next unless @evidence.fetch(member.task_source_id).fact("active_effort")

        item = member.effort_observations.find { |observation| observation["scope"] == "process" }
        frequency = item&.fetch("frequency")
        next unless frequency

        rate = frequency["max"] || frequency["min"]
        multiplier = Findings::AnnualHours::OCCURRENCES_PER_YEAR[frequency["unit"]]
        rate * multiplier if positive_number?(rate) && multiplier
      end.max
    end

    def risk_signals(known, conflicts)
      risks = []
      risks << "Reported exceptions need validation." if known.include?("exceptions")
      risks << "Reported dependencies may affect ownership or approvals." if known.include?("dependencies")
      risks << "Reported friction warrants checking rework or quality impact." if known.include?("bottlenecks") || @finding_links.any?
      waiting = @memberships.any? do |member|
        evidence = @evidence.fetch(member.task_source_id)
        member.effort_observations.any? do |item|
          next false unless item["effort_type"] == "waiting"

          if item["scope"] == "process"
            evidence.fact("active_effort").present?
          else
            evidence.fact("bottlenecks").present? || evidence.legacy_slot("friction_cost").present?
          end
        end
      end
      risks << "Waiting was reported separately from active work." if waiting
      risks << "Discovery contains conflicting accounts." if conflicts.any?
      risks << "Possible overlap with other clusters could lead to double counting." if @overlaps.any? ||
        @revision.effort_summary["status"].in?(%w[potential_overlap unknown_overlap])
      if @clarifications.any?
        risks << "Open clarification may change the effort estimate or which participants are needed."
      end
      risks
    end

    def objectives_for(known, conflicts, workload, frequency)
      objectives = OBJECTIVES.filter_map { |field, question| question if !known.include?(field) || conflicts.include?(field) }
      objectives << OBJECTIVES.fetch("frequency_volume") unless frequency
      objectives << OBJECTIVES.fetch("active_effort") unless workload
      objectives << "Validate which reported friction is avoidable and how much effort it consumes." if
        known.include?("bottlenecks") || @finding_links.any?
      objectives << "Validate the reported exception path and controls." if known.include?("exceptions")
      objectives.unshift("Compare process boundaries and confirm whether the reported work overlaps.") if @overlaps.any?
      objectives.unshift("Resolve the conflicting Discovery accounts with the participant.") if conflicts.any?
      objectives.unshift("Review the open consolidation clarification before defining the investigation scope.") if @clarifications.any?
      objectives.uniq
    end

    def unknowns(known, conflicts, workload, frequency, release)
      (OBJECTIVES.keys - known).map { |field| "missing:#{field}" } +
        conflicts.map { |field| "conflict:#{field}" } +
        [
          ("unquantified_active_workload" unless workload),
          ("unquantified_frequency" unless frequency),
          ("released_effort_unvalidated" unless release),
          ("cross_cluster_overlap_unresolved" if @overlaps.any?)
        ].compact + @clarifications.flat_map { |request| request.dig("details", "unknowns") }.uniq
    end

    def confidence_for(sources, conflicts)
      corroborating_employees = sources.zip(@sources).filter_map do |coverage, source|
        source.employee_id if (CORE - coverage.fetch("message_anchored_core_fields")).empty?
      end.uniq
      if corroborating_employees.size >= 2 && conflicts.empty? && @overlaps.empty?
        "high"
      elsif sources.any? { |source| source.fetch("message_anchored_core_fields").any? } && conflicts.empty?
        "medium"
      else
        "low"
      end
    end

    def scoring(known, workload, release, frequency, risks, objectives, confidence, grounded)
      effort = [24, 120, 240, 480].count { |threshold| workload && workload["annual_hours_min"] >= threshold }
      effort = [effort, 2].min if @overlaps.any?
      {
        "workload" => effort,
        "avoidable_effort_evidence" => release ? 2 : 0,
        "frequency" => [12, 48, 240].count { |threshold| frequency && frequency >= threshold },
        "complexity" => (known & %w[tools dependencies exceptions]).size,
        "risk" => [risks.size, 3].min,
        "evidence_quality" => { "low" => 0, "medium" => 2, "high" => 3 }.fetch(confidence),
        "investigation_usefulness" => grounded ? [objectives.size, 3].min : 0,
        "reviewed_finding" => @finding_links.any? { |finding| finding["status"] == "approved" } ? 1 : 0,
        "business_goal_keyword_alignment" => goal_alignment? ? 1 : 0
      }
    end

    def primary_focus(scores)
      return "scope" if @overlaps.any?
      return "risk" if scores.fetch("risk") >= 2
      return "effort" if scores.fetch("workload").positive? || scores.fetch("avoidable_effort_evidence").positive?

      "process"
    end

    def goal_alignment?
      terms = @sources.flat_map { |source| goal_terms(source.name) }.uniq
      @goals.any? { |goal| (terms & goal_terms(goal)).size >= 2 }
    end

    def goal_terms(text)
      text.downcase.scan(/[[:alnum:]]{4,}/) - GOAL_STOP_WORDS
    end

    def positive_number?(value)
      value.is_a?(Numeric) && value.finite? && value.positive?
    end
  end
end
