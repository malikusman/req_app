# frozen_string_literal: true

module Intelligence
  class PatternUpsertService
    def self.call(company:, patterns:, reconcile_stale: false)
      new(company: company, patterns: patterns, reconcile_stale: reconcile_stale).call
    end

    def initialize(company:, patterns:, reconcile_stale: false)
      @company = company
      @patterns = patterns
      @reconcile_stale = reconcile_stale
    end

    def call
      seen_ids = []

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
            # The fresh confidence, not the historical maximum. `max` meant a
            # pattern that peaked once stayed at that confidence forever even as
            # its evidence weakened, and forcing status to "confirmed" on every
            # pass meant an emerging pattern could never go back to emerging.
            confidence: attrs[:confidence],
            linked_signal_ids: attrs[:linked_signal_ids],
            departments: canonical_departments(attrs[:departments]),
            last_updated_at: now,
            status: attrs[:confidence] >= 0.75 ? "confirmed" : "emerging"
          )
        end

        seen_ids << pattern.id
      end

      # Patterns had no reconciliation at all, so one detected once lived
      # forever — which would have quietly defeated PatternDetector's new
      # MAX_CROSS_DEPARTMENT cap, and more generally kept reporting a pattern
      # whose evidence had gone. Mirrors SignalUpsertService. Nothing holds a
      # foreign key to patterns; recommendations and agentic ideas reference
      # them by id in jsonb arrays that are read defensively, and
      # RecommendationSynthesizer re-runs immediately after this in the same
      # aggregation pass.
      @company.patterns.where.not(id: seen_ids).destroy_all if @reconcile_stale

      seen_ids
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
