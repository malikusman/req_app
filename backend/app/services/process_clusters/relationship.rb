# frozen_string_literal: true

module ProcessClusters
  class Relationship
    GROUPABLE = %w[same_work different_stages].freeze
    STOP_WORDS = %w[a an and are as at be by for from in into is it of on or that the their then to we with].freeze

    def initialize(evidence)
      @evidence = evidence
      @facts = {}
    end

    def compare(left, right)
      return if left.conversation_id == right.conversation_id

      a = facts(left)
      b = facts(right)
      return if [a, b].any? { |entry| informative(entry[:steps]).uniq.size < 3 }

      if match?(a[:steps], b[:steps]) && match?(a[:trigger], b[:trigger]) && match?(a[:output], b[:output])
        return relationship(left, right, "same_work", "Recorded steps, trigger and output agree.")
      end

      handoff = stage_handoff(left, right, a, b) unless a[:steps] == b[:steps]
      return handoff if handoff

      if similar_steps?(a[:steps], b[:steps])
        relationship(left, right, "uncertain", "Recorded steps overlap, but the process boundaries or handoff do not establish a match.")
      elsif match?(a[:trigger], b[:trigger]) || match?(a[:output], b[:output])
        relationship(left, right, "related_distinct", "A recorded boundary agrees, but the activities describe distinct steps.")
      end
    end

    private

    def stage_handoff(left, right, a, b)
      forward = match?(a[:output], b[:trigger], minimum: 4)
      reverse = match?(b[:output], a[:trigger], minimum: 4)
      if forward && reverse
        return relationship(left, right, "uncertain", "Both activities appear to feed each other. Stage order is unresolved.")
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
          output: tokens(evidence.fact("output_recipient")&.fetch("value", nil))
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

    def similar_steps?(a, b)
      a = informative(a)
      b = informative(b)
      common = (a & b).size
      common >= 3 && common * 2 >= (a | b).size
    end

    def relationship(left, right, kind, rationale)
      { "source_ids" => [left.id, right.id], "kind" => kind, "rationale" => rationale }
    end
  end
end
