# frozen_string_literal: true

module Synthesis
  # One judged relationship between two work items, as the pure-code stages
  # (cluster assembly, effort normalisation, sampling) read it — whether it came
  # from P10, a fallback or a consultant.
  Edge = Struct.new(:from_id, :to_id, :relationship_type, :same_execution, :confidence, :recommendation,
                    :variant_assessment, :rationale, keyword_init: true) do
    def self.from(relationship)
      new(from_id: relationship.from_finding_id, to_id: relationship.to_finding_id,
          relationship_type: relationship.relationship_type, same_execution: relationship.same_execution,
          confidence: relationship.confidence, recommendation: relationship.recommendation,
          variant_assessment: relationship.variant_assessment || {}, rationale: relationship.rationale)
    end

    # Whether the two items belong in one cluster (Doc 10 §8.3: never at LOW).
    def clusters? = ProcessRelationship::CLUSTERING.include?(recommendation) && confidence != "LOW"

    def touches?(id) = from_id == id || to_id == id
    def other(id) = from_id == id ? to_id : from_id
  end
end
