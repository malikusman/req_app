# frozen_string_literal: true

module Reports
  class DeltaCalculator
    def self.call(company:, previous_report: nil)
      new(company: company, previous_report: previous_report).call
    end

    def initialize(company:, previous_report: nil)
      @company = company
      @previous_report = previous_report
    end

    def call
      current_signals = @company.company_signals.pluck(:id, :label, :strength)
      current_patterns = @company.patterns.pluck(:id, :title)
      current_recs = @company.recommendations.published.pluck(:id, :title)

      return empty_delta if @previous_report.blank?

      prev = @previous_report.report_snapshot
      prev_signal_ids = Set.new(prev.dig("signals")&.map { |s| s["id"] } || [])
      prev_pattern_ids = Set.new(prev.dig("patterns")&.map { |p| p["id"] } || [])
      prev_rec_ids = Set.new(prev.dig("recommendations")&.map { |r| r["id"] } || [])

      new_signals = current_signals.reject { |id, _, _| prev_signal_ids.include?(id) }
      new_patterns = current_patterns.reject { |id, _| prev_pattern_ids.include?(id) }
      new_recs = current_recs.reject { |id, _| prev_rec_ids.include?(id) }

      strengthened = current_signals.select do |id, label, strength|
        prev_signal = prev.dig("signals")&.find { |s| s["id"] == id }
        prev_signal && strength > (prev_signal["strength"] || 0) + 0.1
      end.map { |_, label, strength| { "label" => label, "strength" => strength } }

      summary_parts = []
      summary_parts << "#{new_patterns.size} new pattern#{'s' if new_patterns.size != 1}" if new_patterns.any?
      summary_parts << "#{new_recs.size} new recommendation#{'s' if new_recs.size != 1}" if new_recs.any?
      summary_parts << "#{new_signals.size} new signal#{'s' if new_signals.size != 1}" if new_signals.any?

      {
        "new_signals" => new_signals.map { |id, label, strength| { "id" => id, "label" => label, "strength" => strength } },
        "new_patterns" => new_patterns.map { |id, title| { "id" => id, "title" => title } },
        "new_recommendations" => new_recs.map { |id, title| { "id" => id, "title" => title } },
        "strengthened_signals" => strengthened,
        "summary" => summary_parts.any? ? "#{summary_parts.join(', ')} since Report v#{@previous_report.version}" : "No major changes since previous report"
      }
    end

    private

    def empty_delta
      {
        "new_signals" => [],
        "new_patterns" => [],
        "new_recommendations" => [],
        "strengthened_signals" => [],
        "summary" => "Initial discovery report"
      }
    end
  end
end
