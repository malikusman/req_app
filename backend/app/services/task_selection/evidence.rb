# frozen_string_literal: true

module TaskSelection
  class Evidence
    CLASSIFICATIONS = %w[SHARED_IDENTICAL SHARED_VARIANT DISTINCT UNRESOLVED].freeze

    attr_reader :proposals, :sources, :relationships, :participants

    def initialize(run)
      @run = run
      @sources = {}
      @relationships = []
      @proposals = run.candidates.joins(process_cluster_revision: :process_cluster)
                      .where(process_clusters: { company_id: run.company_id })
                      .includes(process_cluster_revision: { memberships: :task_source })
                      .order(Arel.sql("rank NULLS LAST, score DESC, task_candidate_proposals.id")).map { |candidate| proposal(candidate) }
      @relationships.select! { |pair| pair.fetch("source_ids").all? { |id| sources.key?(id) } }
      @relationships.uniq! { |pair| pair.fetch("source_ids").sort }
      @participants = Employee.where(company_id: run.company_id, id: sources.values.pluck("employee_id"))
                              .where.not(participation_status: "declined")
                              .order(:display_name, :id).pluck(:id, :display_name, :consent_given_at).map do |id, name, consent|
        { "id" => id, "name" => name, "discovery_consent_recorded" => consent.present? }
      end
    end

    def participants_for(task)
      employee_ids = task.fetch("source_ids").map { |id| sources.fetch(id).fetch("employee_id") }.to_set
      participants.select { |person| employee_ids.include?(person.fetch("id")) }
    end

    def proposal(candidate)
      revision = candidate.process_cluster_revision
      ids = revision.memberships.sort_by(&:id).filter_map do |member|
        source = member.task_source
        next unless source.company_id == @run.company_id

        @sources[source.id] ||= source.as_json(only: %i[id employee_id conversation_id name version discovery_revision finding_id])
                                     .merge("effort_observations" => member.effort_observations.map do |item|
          item.slice("scope", "effort_type", "annual_hours_min", "annual_hours_max", "calculation_basis", "calculation_reason")
              .merge("frequency" => item.fetch("frequency").slice("min", "max", "unit"),
                     "duration" => item.fetch("duration").slice("min", "max", "unit"))
        end)
        source.id
      end
      @relationships.concat(revision.relationships.map do |pair|
        request = pair["clarification_request"]
        pair.slice("source_ids", "kind", "classification", "rationale", "missing_evidence").merge(
          "clarification_request" => request && request.slice("id", "version", "status").merge(
            request.fetch("details").slice("missing_evidence", "why_it_matters", "unknowns", "impacts")
          )
        )
      end)
      candidate.as_json(only: %i[id title disposition disposition_reason rank score priority confidence]).merge(
        "process_cluster_id" => revision.process_cluster_id, "process_cluster_revision_id" => revision.id,
        "process_cluster_revision_number" => revision.number, "source_ids" => ids,
        "assessment" => candidate.assessment.slice("basis", "observed_workload", "possible_released_effort", "risks", "unknowns",
                                                   "deep_dive_objectives", "evidence_sources", "findings", "potential_overlap_cluster_ids")
      )
    end

    def effective_effort(task, selected, overrides)
      ids = task.fetch("source_ids")
      observations = ids.filter_map do |id|
        assumption = task.fetch("effort_assumptions")[id.to_s]
        next assumption if assumption

        sources.fetch(id).fetch("effort_observations").find { |item| item["scope"] == "process" && item["effort_type"] == "active" }
      end
      return { "status" => "unknown" } if ids.empty?
      return { "status" => "withheld_shared_evidence" } if selected.any? do |other|
        other["id"] != task["id"] && ids.intersect?(other["source_ids"])
      end
      other_ids = selected.reject { |other| other["id"] == task["id"] }.flat_map { |other| other["source_ids"] }
      if relationships.any? { |pair| overlapping?(pair) && ids.intersect?(pair["source_ids"]) && other_ids.intersect?(pair["source_ids"] - ids) }
        return { "status" => "withheld_possible_overlap" }
      end

      pairs = ids.combination(2).to_a
      independent = pairs.all? do |pair|
        reported = relationships.find { |relationship| relationship.fetch("source_ids").sort == pair.sort }
        overrides.dig(pair.sort.join(":"), "classification") == "DISTINCT" ||
          (!overrides.key?(pair.sort.join(":")) && reported&.fetch("kind", nil) == "different_stages")
      end
      if ids.size > 1 && (!independent || ids.map { |id| sources.fetch(id).fetch("employee_id") }.uniq.size != ids.size)
        return { "status" => "withheld_possible_overlap" }
      end
      if observations.size != ids.size || observations.any? { |item| item.values_at("annual_hours_min", "annual_hours_max").any?(&:nil?) }
        return { "status" => "unknown_active_effort" }
      end

      judgment = observations.any? { |item| item["basis"] == "consultant_judgment" } ||
                 pairs.any? { |pair| overrides.key?(pair.sort.join(":")) }
      {
        "status" => judgment ? "conditional_consultant_assumption" : "reported_active_workload",
        "annual_hours_min" => observations.sum { |item| item.fetch("annual_hours_min") },
        "annual_hours_max" => observations.sum { |item| item.fetch("annual_hours_max") }
      }
    end

    def gaps(task, selected, overrides)
      ids = task.fetch("source_ids")
      gaps = relationships.filter_map do |pair|
        next unless ids.intersect?(pair.fetch("source_ids"))
        next unless pair["classification"] == "UNRESOLVED" || pair["kind"] == "uncertain" ||
                    pair.dig("clarification_request", "status") == "open"

        "Unresolved relationship between sources #{pair.fetch('source_ids').join(' and ')}."
      end
      task_proposals = proposals.select { |proposal| task.fetch("proposal_ids").include?(proposal.fetch("id")) }
      if task_proposals.any? { |proposal| proposal.dig("assessment", "potential_overlap_cluster_ids").present? }
        gaps << "The recommendation flags potential overlap with another process."
      end
      overrides.each_value do |override|
        if override["classification"] == "UNRESOLVED" && ids.intersect?(override.fetch("source_ids"))
          gaps << "Consultant flagged an unresolved relationship between sources #{override.fetch('source_ids').join(' and ')}."
        end
      end
      gaps << "No linked Discovery evidence." if ids.empty?
      gaps << "Scope may overlap another selected task. Some source versions are reused." if selected.any? do |other|
        other["id"] != task["id"] && ids.intersect?(other["source_ids"])
      end
      employees = ids.map { |id| sources.fetch(id).fetch("employee_id") }
      gaps << "No participant selected." if task.fetch("participant_ids").empty?
      task.fetch("participant_ids").each do |id|
        person = participants.find { |participant| participant["id"] == id }
        if !employees.include?(id)
          gaps << "A saved participant has no linked evidence for this task."
        elsif !person
          gaps << "A saved participant is no longer eligible."
        elsif !person["discovery_consent_recorded"]
          gaps << "A participant has no recorded Discovery consent."
        end
      end
      gaps << "Active workload is unresolved or may overlap." if task.dig("effective_effort", "status").match?(/\A(?:unknown|withheld)/)
      gaps
    end

    private

    def overlapping?(pair)
      pair["classification"].in?(%w[UNRESOLVED SHARED_IDENTICAL SHARED_VARIANT]) ||
        pair["kind"].in?(%w[uncertain same_work shared_variant])
    end
  end
end
