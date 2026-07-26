# frozen_string_literal: true

module Intelligence
  class PatternDetector
    # Align with SignalExtractor's floor so single-source keyword hits still
    # participate in combo / co-occurrence rules.
    MIN_STRENGTH = 0.35
    ANCHOR_STRENGTH = 0.65

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      signals = @company.company_signals.where("strength >= ?", MIN_STRENGTH).order(strength: :desc).to_a
      return [] if signals.size < 2

      patterns = []

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

      # Departments are merged onto one signal row per (type, label); multi-dept
      # coverage is an array on that row, not multiple rows of the same type.
      signals.select { |s| Array(s.departments).uniq.size >= 2 }.each do |signal|
        depts = Array(signal.departments).uniq
        patterns << build_pattern(
          title: "#{signal.label} across departments",
          description: "This pain point appears in #{depts.join(', ')}.",
          signal_ids: [signal.id],
          confidence: signal.strength,
          departments: depts
        )
      end

      patterns.uniq { |p| p[:title] }
    end

    private

    def combo_signal_ids(signals, types)
      typed = types.map { |t| signals.find { |s| s.signal_type == t } }
      return nil if typed.any?(&:nil?)
      return nil unless typed.any? { |s| s.strength >= ANCHOR_STRENGTH }

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
