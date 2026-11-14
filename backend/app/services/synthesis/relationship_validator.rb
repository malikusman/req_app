# frozen_string_literal: true

module Synthesis
  # Checks P10's verdict on a pair before anything is stored (P10 §9). The
  # direction of every correction is the same: towards keeping things apart.
  #
  #   - Unknown relationship, confidence or recommendation: the reply is unusable.
  #   - Anything but INDEPENDENT must give the evidence for it.
  #   - AUTO_CLUSTER only at HIGH for SAME_PROCESS or SHARED_SUBPROCESS; any other
  #     auto-cluster becomes provisional, and nothing clusters at LOW.
  #   - INDEPENDENT, DEPENDENCY and ROOT_CAUSE_LINKED never cluster.
  #   - CLARIFY must say what to ask, or it becomes a consultant review.
  #   - No numbers: P10 describes overlap in words, and the platform does the
  #     arithmetic (Doc 10 §20.2). A sentence carrying a figure is dropped.
  # Each correction is recorded, so the run says what the model was overruled on.
  class RelationshipValidator
    class Invalid < StandardError; end

    TEST_VALUES = %w[YES NO PARTLY UNKNOWN].freeze
    FACTORS = %w[SYSTEMS OUTPUTS VOLUMES EXCEPTIONS CUSTOMER_SEGMENT PRODUCT LOCATION VALUE_THRESHOLD
                 ROLE_SPECIALISATION NONE].freeze
    NEVER_CLUSTER = %w[INDEPENDENT DEPENDENCY ROOT_CAUSE_LINKED].freeze
    AUTO_ALLOWED = %w[SAME_PROCESS SHARED_SUBPROCESS].freeze
    DIGIT = /\d/

    attr_reader :corrections

    def initialize(raw)
      @raw = raw.is_a?(Hash) ? raw : {}
      @corrections = []
    end

    def call
      type = enum(@raw["relationship"], ProcessRelationship::TYPES, "relationship")
      confidence = enum(@raw["confidence"], ProcessRelationship::CONFIDENCES, "confidence")
      recommendation = enum(@raw["recommendation"], ProcessRelationship::RECOMMENDATIONS, "recommendation")
      evidence_for = strings(@raw["evidence_for"], "evidence_for")
      raise Invalid, "no evidence for #{type}" if type != "INDEPENDENT" && evidence_for.empty?

      recommendation = settle(type, confidence, recommendation)
      overlap = @raw["effort_overlap"].is_a?(Hash) ? @raw["effort_overlap"] : {}
      {
        "relationship_type" => type, "confidence" => confidence, "recommendation" => recommendation,
        "evidence_for" => evidence_for, "evidence_against" => strings(@raw["evidence_against"], "evidence_against"),
        "tests" => tests, "variant_assessment" => variant_assessment,
        "same_execution" => ProcessRelationship::SAME_EXECUTION.include?(overlap["same_execution"]) ? overlap["same_execution"] : "UNKNOWN",
        "effort_note" => text(overlap["note"], "effort_overlap.note"),
        "rationale" => text(@raw["rationale"], "rationale"),
        "clarification" => recommendation == "CLARIFY" ? text(@raw["clarification_needed"], "clarification_needed") : nil
      }
    end

    private

    def settle(type, confidence, recommendation)
      if NEVER_CLUSTER.include?(type) && ProcessRelationship::CLUSTERING.include?(recommendation)
        correct("#{type} never clusters; kept separate")
        return "KEEP_SEPARATE"
      end
      if confidence == "LOW" && ProcessRelationship::CLUSTERING.include?(recommendation)
        correct("nothing clusters at LOW confidence; kept separate")
        return "KEEP_SEPARATE"
      end
      if recommendation == "AUTO_CLUSTER" && !(confidence == "HIGH" && AUTO_ALLOWED.include?(type))
        correct("AUTO_CLUSTER needs HIGH confidence and SAME_PROCESS or SHARED_SUBPROCESS; made provisional")
        return "PROVISIONAL_CLUSTER"
      end
      if recommendation == "CLARIFY" && @raw["clarification_needed"].to_s.strip.empty?
        correct("CLARIFY without a question; sent to consultant review")
        return "CONSULTANT_REVIEW"
      end
      recommendation
    end

    def tests
      raw = @raw["tests"].is_a?(Hash) ? @raw["tests"] : {}
      raw.each_with_object({}) do |(key, value), out|
        out[key.to_s] = value if TEST_VALUES.include?(value)
      end
    end

    def variant_assessment
      raw = @raw["variant_assessment"].is_a?(Hash) ? @raw["variant_assessment"] : {}
      {
        "material_differences" => strings(raw["material_differences"], "variant_assessment.material_differences"),
        "would_one_deep_dive_represent_both" => (%w[YES NO UNSURE] & [raw["would_one_deep_dive_represent_both"]]).first,
        "distinguishing_factors" => Array(raw["distinguishing_factors"]) & FACTORS
      }.compact
    end

    def enum(value, allowed, field)
      return value if allowed.include?(value)

      raise Invalid, "#{field} #{value.inspect} not recognised"
    end

    def strings(value, field)
      Array(value).filter_map { |s| text(s, field) }
    end

    def text(value, field)
      value = value.to_s.strip
      return nil if value.empty?

      if value.match?(DIGIT)
        correct("#{field}: dropped text carrying a figure")
        return nil
      end
      value
    end

    def correct(note) = @corrections << note
  end
end
