# frozen_string_literal: true

module Intelligence
  class PatternUpsertService
    def self.call(company:, patterns:)
      new(company: company, patterns: patterns).call
    end

    def initialize(company:, patterns:)
      @company = company
      @patterns = patterns
    end

    def call
      @patterns.each do |attrs|
        pattern = Pattern.find_or_initialize_by(company: @company, title: attrs[:title])
        now = Time.current

        if pattern.new_record?
          pattern.assign_attributes(
            description: attrs[:description],
            confidence: attrs[:confidence],
            departments: canonical_departments(attrs[:departments]),
            linked_signal_ids: attrs[:linked_signal_ids],
            first_seen_at: now,
            last_updated_at: now,
            status: attrs[:confidence] >= 0.75 ? "confirmed" : "emerging"
          )
          pattern.save!
          TimelineRecorder.pattern_detected!(company: @company, pattern: pattern)
        else
          pattern.update!(
            confidence: [pattern.confidence, attrs[:confidence]].max,
            linked_signal_ids: (pattern.linked_signal_ids + attrs[:linked_signal_ids]).uniq,
            departments: canonical_departments(pattern.departments + attrs[:departments]),
            last_updated_at: now,
            status: "confirmed"
          )
        end
      end
    end

    private

    # Dedupe departments case-insensitively (keeping first-seen casing).
    def canonical_departments(list)
      Array(list).map { |d| d.to_s.strip }.reject(&:blank?).each_with_object({}) do |dept, acc|
        acc[dept.downcase] ||= dept
      end.values
    end
  end
end
