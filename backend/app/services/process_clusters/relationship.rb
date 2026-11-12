# frozen_string_literal: true

module ProcessClusters
  class Relationship
    CLASSIFICATIONS = {
      "same_work" => "SHARED_IDENTICAL", "shared_variant" => "SHARED_VARIANT",
      "different_stages" => "DISTINCT", "related_distinct" => "DISTINCT", "uncertain" => "UNRESOLVED"
    }.freeze
    GROUPABLE = %w[same_work shared_variant different_stages].freeze
    OVERLAP_KINDS = %w[same_work shared_variant uncertain].freeze
    SCOPE_FIELDS = %w[trigger_inputs steps_decisions output_recipient tools].freeze
    STOP_WORDS = %w[a an and are as at be by for from in into is it of on or that the their then to we with].freeze

    def initialize(evidence)
      @evidence = evidence
      @facts = {}
    end

    def compare(left, right)
      return if left.conversation_id == right.conversation_id

      a = facts(left)
      b = facts(right)
      same_trigger = match?(a[:trigger], b[:trigger])
      same_output = match?(a[:output], b[:output])
      if [a, b].any? { |entry| informative(entry[:steps]).uniq.size < 3 }
        return unresolved(left, right, a, b, "A boundary agrees, but the recorded steps are insufficient to compare the activities.") if
          same_trigger || same_output
        return
      end

      overlapping_steps = similar_steps?(a[:steps], b[:steps])
      if a[:conflict] || b[:conflict]
        return unresolved(left, right, a, b, "Conflicting Discovery facts prevent classification.") if
          overlapping_steps || same_trigger || same_output
        return
      end

      if same_trigger && same_output
        if match?(a[:steps], b[:steps])
          if a[:tools].any? && b[:tools].any? && a[:tools] != b[:tools]
            return relationship(left, right, "shared_variant", "Recorded scope and steps agree, but the reported tools differ.")
          end
          return relationship(left, right, "same_work", "Recorded steps, trigger and output agree.")
        end
        if similar_steps?(a[:steps], b[:steps], variant: true)
          return relationship(left, right, "shared_variant", "Recorded boundaries agree and the activities share most step terms, with different recorded steps.")
        end
        return unresolved(left, right, a, b, "Recorded boundaries agree, but the evidence does not explain how the different steps relate.")
      end

      handoff = stage_handoff(left, right, a, b) unless a[:steps] == b[:steps]
      return handoff if handoff

      if overlapping_steps
        unresolved(left, right, a, b, "Recorded steps overlap, but the scope or handoff does not establish a match.")
      elsif same_trigger || same_output
        relationship(left, right, "related_distinct", "A recorded boundary agrees, but the activities describe distinct steps.")
      end
    end

    private

    def stage_handoff(left, right, a, b)
      forward = match?(a[:output], b[:trigger], minimum: 4)
      reverse = match?(b[:output], a[:trigger], minimum: 4)
      if forward && reverse
        return unresolved(left, right, a, b, "Both activities appear to feed each other. Stage order is unresolved.")
      end
      return unless forward || reverse

      first, second = forward ? [left, right] : [right, left]
      relationship(first, second, "different_stages", "The first activity's recorded output matches the second activity's trigger.")
    end

    def facts(source)
      @facts[source.id] ||= begin
        evidence = @evidence.fetch(source.id)
        steps = evidence.fact("steps_decisions") || evidence.legacy_slot("how_it_works")
        {
          steps: tokens(steps&.fetch("value", nil)),
          trigger: tokens(evidence.fact("trigger_inputs")&.fetch("value", nil)),
          output: tokens(evidence.fact("output_recipient")&.fetch("value", nil)),
          tools: tokens(evidence.fact("tools")&.fetch("value", nil)),
          conflict: SCOPE_FIELDS.any? { |field| evidence.fact(field, status: "conflict") }
        }
      end
    end

    def tokens(value)
      value.to_s.downcase.scan(/[[:alnum:]]+/)
    end

    def informative(words)
      words - STOP_WORDS
    end

    def match?(a, b, minimum: 3)
      a == b && informative(a).uniq.size >= minimum
    end

    def similar_steps?(a, b, variant: false)
      a = informative(a)
      b = informative(b)
      common = (a & b).size
      combined = (a | b).size
      variant ? common >= 4 && common * 3 >= combined * 2 : common >= 3 && common * 2 >= combined
    end

    def unresolved(left, right, a, b, rationale)
      missing = []
      missing << "Comparable trigger and inputs for both activities." unless match?(a[:trigger], b[:trigger])
      missing << "Comparable output and recipient for both activities." unless match?(a[:output], b[:output])
      missing << "Evidence of the steps, differences in procedure, and any handoff."
      missing << "Evidence resolving the conflicting Discovery facts." if a[:conflict] || b[:conflict]
      relationship(left, right, "uncertain", rationale).merge("missing_evidence" => missing)
    end

    def relationship(left, right, kind, rationale)
      { "source_ids" => [left.id, right.id], "kind" => kind,
        "classification" => CLASSIFICATIONS.fetch(kind), "rationale" => rationale }
    end
  end
end
