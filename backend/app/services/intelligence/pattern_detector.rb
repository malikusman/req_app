# frozen_string_literal: true

module Intelligence
  class PatternDetector
    # Align with SignalExtractor's floor so single-source keyword hits still
    # participate in combo / co-occurrence rules.
    MIN_STRENGTH = 0.35
    ANCHOR_STRENGTH = 0.65

    # The cross-department rule gets a lower floor than the combo rules, and the
    # asymmetry is deliberate:
    #
    #   * A combo pattern asserts a fixed, high confidence (0.82 / 0.78) that two
    #     signal TYPES reinforce each other. On thin evidence that claim is
    #     unearned, so MIN_STRENGTH guards it.
    #   * A cross-department pattern reports its own signal's strength as its
    #     confidence, so a thinly-evidenced one surfaces as a LOW-confidence
    #     pattern — the report states the uncertainty rather than hiding it.
    #     And the spread itself is corroboration: two teams independently
    #     describing the same friction is the finding, whatever the raw
    #     keyword-hit count.
    #
    # Under one shared floor, two employees in different departments reporting
    # the same problem produced a 0.28-strength signal and therefore no pattern
    # at all — which is how a real report showed "Patterns detected (0)" beside
    # six healthy signals. Matches SignalExtractor's own 0.2 floor.
    CROSS_DEPARTMENT_MIN_STRENGTH = 0.2

    # Ranked and capped. Once departments are attributed properly, MOST signals
    # in a multi-department company span two teams, so an uncapped rule emitted
    # one near-identical "<signal> across departments" pattern per signal type —
    # seven of them on one company, which says less than the signal list already
    # does. The value of this rule is surfacing the friction that cuts widest,
    # not restating every signal's department array, so only the strongest few
    # become patterns.
    MAX_CROSS_DEPARTMENT = 3

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
      # Company-overridable, same mechanism as report_thresholds. The constants
      # above are the shipped defaults; how readily a pattern should form is a
      # product-judgement call about false positives on small samples, so it is
      # a setting rather than a decision baked into the code.
      @thresholds = company.merged_settings.fetch("pattern_thresholds", {})
    end

    def min_strength
      threshold("min_strength", MIN_STRENGTH)
    end

    def anchor_strength
      threshold("anchor_strength", ANCHOR_STRENGTH)
    end

    def cross_department_min_strength
      threshold("cross_department_min_strength", CROSS_DEPARTMENT_MIN_STRENGTH)
    end

    def max_cross_department
      threshold("max_cross_department", MAX_CROSS_DEPARTMENT).to_i
    end

    def call
      all_signals = @company.company_signals.order(strength: :desc).to_a
      signals = all_signals.select { |s| s.strength.to_f >= min_strength }
      patterns = []

      patterns.concat(cross_department_patterns(all_signals))
      return patterns.uniq { |p| p[:title] } if signals.size < 2

      if (ids = combo_signal_ids(signals, %w[approval_bottleneck manual_process]))
        patterns << build_pattern(
          title: "Approval bottleneck across manual workflows",
          description: "Multiple teams report manual work combined with slow approvals.",
          signal_ids: ids,
          confidence: 0.82,
          departments: departments_for(signals, ids)
        )
      end

      if (ids = combo_signal_ids(signals, %w[data_silo time_sink]))
        patterns << build_pattern(
          title: "Reconciliation drag from fragmented data",
          description: "Data silos and repetitive time sinks reinforce each other in day-to-day work.",
          signal_ids: ids,
          confidence: 0.78,
          departments: departments_for(signals, ids)
        )
      end

      patterns.uniq { |p| p[:title] }
    end

    private

    # Departments are merged onto one signal row per (type, label); multi-dept
    # coverage is an array on that row, not multiple rows of the same type.
    def cross_department_patterns(signals)
      signals
        .select { |s| s.strength.to_f >= cross_department_min_strength }
        .select { |s| Array(s.departments).uniq.size >= 2 }
        # Widest spread first, then strongest — a friction in three departments
        # is a bigger finding than a slightly stronger one in two.
        .sort_by { |s| [-Array(s.departments).uniq.size, -s.strength.to_f] }
        .first(max_cross_department)
        .map do |signal|
          depts = Array(signal.departments).uniq
          build_pattern(
            title: "#{signal.label} across departments",
            description: "This pain point appears in #{depts.join(', ')}.",
            signal_ids: [signal.id],
            # The signal's own strength, so a thin cross-department finding
            # reads as low confidence rather than as a confident claim.
            confidence: signal.strength,
            departments: depts
          )
        end
    end

    def threshold(name, default)
      value = @thresholds[name]
      value.nil? ? default : value.to_f
    end

    def combo_signal_ids(signals, types)
      typed = types.map { |t| signals.find { |s| s.signal_type == t } }
      return nil if typed.any?(&:nil?)
      return nil unless typed.any? { |s| s.strength >= anchor_strength }

      typed.map(&:id)
    end

    def departments_for(signals, ids)
      signals.select { |s| ids.include?(s.id) }.flat_map { |s| Array(s.departments) }.uniq
    end

    def build_pattern(title:, description:, signal_ids:, confidence:, departments:)
      { title: title, description: description, linked_signal_ids: signal_ids, confidence: confidence.round(2), departments: departments }
    end
  end
end
