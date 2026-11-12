# frozen_string_literal: true

module ProcessClusters
  module EffortReconciliation
    def self.observations(evidence)
      if evidence.source.source_kind == "workflow_ledger"
        [
          observation("process", evidence.fact("active_effort")),
          observation("bottleneck", evidence.fact("bottlenecks"))
        ].compact
      else
        [observation("bottleneck", evidence.legacy_slot("friction_cost"))].compact
      end
    end

    def self.observation(scope, entry)
      raw = entry&.fetch("effort", nil)
      return unless raw.is_a?(Hash)

      frequency = raw["frequency"].to_h.slice("min", "max", "unit", "as_said")
      duration = raw["duration"].to_h.slice("min", "max", "unit", "as_said")
      effort_type = raw["effort_type"].presence || "unknown"
      observation = {
        "scope" => scope, "effort_type" => effort_type, "frequency" => frequency, "duration" => duration
      }
      return observation unless scope == "process" && effort_type == "active"

      hours = Findings::AnnualHours.call(
        frequency_min: frequency["min"], frequency_max: frequency["max"], frequency_unit: frequency["unit"],
        duration_min: duration["min"], duration_max: duration["max"], duration_unit: duration["unit"],
        effort_type: effort_type
      )
      observation.merge("annual_hours_min" => hours.min, "annual_hours_max" => hours.max,
                        "calculation_basis" => hours.basis, "calculation_reason" => hours.reason)
    end

    def self.summarize(sources, observations, relationships)
      per_source = sources.map { |source| observations.fetch(source.id) }
      active = per_source.map do |items|
        items.find { |item| item["scope"] == "process" && item["annual_hours_min"].present? }
      end
      waiting_count = per_source.flatten.count { |item| item["effort_type"] == "waiting" }
      status, included = combination(sources, active, relationships)
      {
        "status" => status,
        "annual_hours_min" => included&.sum { |item| item.fetch("annual_hours_min") },
        "annual_hours_max" => included&.sum { |item| item.fetch("annual_hours_max") },
        "quantified_source_count" => active.compact.size,
        "waiting_observation_count" => waiting_count
      }
    end

    def self.combination(sources, active, relationships)
      return ["unknown", nil] if sources.empty?
      if sources.one?
        return active.first ? ["independent_observation", active] : ["unknown", nil]
      end

      if relationships.any? { |relationship| Relationship::OVERLAP_KINDS.include?(relationship["kind"]) }
        return ["potential_overlap", nil]
      end
      if sources.map(&:employee_id).uniq.size != sources.size
        return ["unknown_overlap", nil]
      end
      return ["separate_stages_incomplete", nil] if active.any?(&:nil?)

      ["separate_stages", active]
    end

    private_class_method :observation, :combination
  end
end
