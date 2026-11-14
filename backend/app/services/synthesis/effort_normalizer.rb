# frozen_string_literal: true

module Synthesis
  # Stage E, the integrity stage (Doc 10 §10, §20.2): what a cluster's work
  # costs once each execution is counted once. The model never does this sum —
  # it only says, in words, whether two items are the same execution; this
  # turns that into figures.
  #
  # The rules (Doc 10 §10.2), by what P10 said about each pair:
  #   - the same execution (YES)              → counted once; across two
  #                                             people, only a consultant's YES
  #                                             is taken as certain
  #   - one person's work named twice         → counted once, whatever P10 said
  #   - different executions (NO)             → both count — including genuine
  #                                             duplication, which is flagged
  #   - unclear, and the same process or a
  #     shared sub-step (UNKNOWN)             → counted once, marked conservative,
  #                                             with a double-count warning
  #   - stages of one process, variants,
  #     duplicated work, dependencies         → each person's own part counts
  #   - waiting time                          → never counted
  # Understating is survivable; overstating is not.
  #
  # Where an execution is counted once, the fuller of the two accounts (the
  # larger range) stands for it.
  #
  # ProcessClusters::EffortReconciliation, in the deep-dive engine, gives no
  # figure at all where work may overlap. The two need one rule
  # (docs/CONSOLIDATION_ENGINES.md §3).
  class EffortNormalizer
    METHOD_VERSION = "EN.v1"
    COLLAPSE_WHEN_UNKNOWN = %w[SAME_PROCESS SHARED_SUBPROCESS].freeze
    SAME_PERSON_TWICE = %w[SAME_PROCESS DUPLICATE_WORK SHARED_SUBPROCESS].freeze

    Result = Struct.new(:raw_min, :raw_max, :dedup_min, :dedup_max, :overlap_adjustments, :conservative_adjustment,
                        :double_count_warning, :warning_reason, :duplication_flag, :participants_counted,
                        :confidence, :waiting_count, :unquantified_count, keyword_init: true)

    # items: WorkItems::Item (or anything with id, employee_id, hours_min,
    # hours_max, waiting?). edges: anything with from_id, to_id,
    # relationship_type, same_execution, confidence.
    def self.call(items:, edges:) = new(items, edges).call

    def initialize(items, edges)
      @items = items.index_by(&:id)
      @edges = edges.select { |e| @items.key?(e.from_id) && @items.key?(e.to_id) }
    end

    def call
      counted = @items.values.select { |i| i.hours? && !i.waiting? }
      adjustments = []
      conservative = false
      warnings = []
      parent = counted.to_h { |i| [i.id, i.id] }

      @certain = Set.new
      @edges.sort_by { |e| [e.from_id, e.to_id] }.each do |edge|
        next unless parent.key?(edge.from_id) && parent.key?(edge.to_id)

        reason = collapse_reason(edge)
        unless reason
          if same_person_same_figures?(edge)
            warnings << "Items #{edge.from_id} and #{edge.to_id} come from one person with the same figures; " \
                        "check they are not one piece of work counted twice"
          end
          next
        end

        union(parent, edge.from_id, edge.to_id)
        if reason == :unclear
          conservative = true
          warnings << "Whether items #{edge.from_id} and #{edge.to_id} are the same execution is unclear; counted once"
        else
          @certain << [edge.from_id, edge.to_id].sort
        end
      end

      groups = counted.group_by { |i| find(parent, i.id) }.values
      dedup_min = 0.0
      dedup_max = 0.0
      groups.each do |group|
        kept = group.max_by { |i| [i.hours_max, i.hours_min, -i.id] }
        dedup_min += kept.hours_min
        dedup_max += kept.hours_max
        (group - [kept]).each do |dropped|
          adjustments << {
            "removed_item_id" => dropped.id, "kept_item_id" => kept.id,
            "removed_min" => dropped.hours_min, "removed_max" => dropped.hours_max,
            "reason" => same_execution?(kept, dropped) ? "Same execution described twice; counted once" :
                                                         "Overlap unclear; counted once to avoid overstating"
          }
        end
      end

      waiting = @items.values.count(&:waiting?)
      unquantified = @items.values.count { |i| !i.waiting? && !i.hours? }
      adjustments << { "reason" => "#{waiting} waiting item(s) not counted as effort" } if waiting.positive?
      adjustments << { "reason" => "#{unquantified} item(s) without figures not counted" } if unquantified.positive?

      Result.new(
        raw_min: round(counted.sum(&:hours_min)), raw_max: round(counted.sum(&:hours_max)),
        dedup_min: round(dedup_min), dedup_max: round(dedup_max),
        overlap_adjustments: adjustments, conservative_adjustment: conservative,
        double_count_warning: warnings.any?, warning_reason: warnings.join(". ").presence,
        duplication_flag: @edges.any? { |e| e.relationship_type == "DUPLICATE_WORK" },
        participants_counted: groups.flatten.map(&:employee_id).compact.uniq.sort,
        confidence: confidence(conservative), waiting_count: waiting, unquantified_count: unquantified
      )
    end

    private

    # Why two items collapse into one execution, or nil when both count.
    #
    # Two rules are the platform's, whatever the model said (Doc 10 §10.2): one
    # person describing the same work twice is counted once; and two different
    # people's accounts are one execution only with the consultant's say-so —
    # until then it is counted once, as unclear, with a warning.
    def collapse_reason(edge)
      a = @items[edge.from_id]
      b = @items[edge.to_id]
      same_person = a.employee_id.present? && a.employee_id == b.employee_id
      return :same_person if same_person && SAME_PERSON_TWICE.include?(edge.relationship_type)
      return(same_person || edge.origin == "CONSULTANT" ? :same_execution : :unclear) if edge.same_execution == "YES"
      return nil if edge.same_execution == "NO"

      :unclear if COLLAPSE_WHEN_UNKNOWN.include?(edge.relationship_type)
    end

    def same_execution?(a, b) = @certain.include?([a.id, b.id].sort)

    def same_person_same_figures?(edge)
      a = @items[edge.from_id]
      b = @items[edge.to_id]
      a.employee_id.present? && a.employee_id == b.employee_id &&
        [a.hours_min, a.hours_max] == [b.hours_min, b.hours_max]
    end

    def confidence(conservative)
      return "LOW" if conservative || @edges.any? { |e| e.confidence == "LOW" }
      return "HIGH" if @edges.all? { |e| e.confidence == "HIGH" }

      "MEDIUM"
    end

    def union(parent, a, b)
      root_a = find(parent, a)
      root_b = find(parent, b)
      parent[root_b] = root_a unless root_a == root_b
    end

    def find(parent, x)
      parent[x] = find(parent, parent[x]) unless parent[x] == x
      parent[x]
    end

    def round(value) = value.to_f.round(1)
  end
end
