# frozen_string_literal: true

module Intelligence
  class PatternDetector
    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      signals = @company.company_signals.where("strength >= ?", 0.4).order(strength: :desc)
      return [] if signals.size < 2

      patterns = []

      if signals.where(signal_type: "approval_bottleneck").exists? && signals.where(signal_type: "manual_process").exists?
        patterns << build_pattern(
          title: "Approval bottleneck across manual workflows",
          description: "Multiple teams report manual work combined with slow approvals.",
          signal_ids: signals.where(signal_type: %w[approval_bottleneck manual_process]).pluck(:id),
          confidence: 0.82,
          departments: signals.flat_map(&:departments).uniq
        )
      end

      cross_dept = signals.group_by(&:signal_type).select { |_, list| list.map(&:departments).flatten.uniq.size >= 2 }
      cross_dept.each do |type, list|
        patterns << build_pattern(
          title: "#{list.first.label} across departments",
          description: "This pain point appears in #{list.map(&:departments).flatten.uniq.join(', ')}.",
          signal_ids: list.map(&:id),
          confidence: list.map(&:strength).sum / list.size,
          departments: list.flat_map(&:departments).uniq
        )
      end

      patterns.uniq { |p| p[:title] }
    end

    private

    def build_pattern(title:, description:, signal_ids:, confidence:, departments:)
      { title: title, description: description, linked_signal_ids: signal_ids, confidence: confidence.round(2), departments: departments }
    end
  end
end
