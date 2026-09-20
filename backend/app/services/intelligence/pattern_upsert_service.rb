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
            confidence_history: [{ "confidence" => attrs[:confidence], "at" => now.iso8601 }],
            status: attrs[:confidence] >= 0.75 ? "confirmed" : "emerging"
          )
          pattern.save!
          TimelineRecorder.pattern_detected!(company: @company, pattern: pattern)
        else
          previous = pattern.confidence.to_f
          fresh = attrs[:confidence].to_f

          pattern.update!(
            # The fresh confidence, not the historical maximum. `max` meant a
            # pattern that peaked once stayed at that confidence forever even as
            # its evidence weakened, and forcing status to "confirmed" on every
            # pass meant an emerging pattern could never go back to emerging.
            #
            # Nothing is lost by that: a material move in either direction is
            # recorded, so a pattern that has weakened can still be seen to have
            # been stronger. Same reason company_signals keeps strength_history.
            confidence: fresh,
            confidence_history: history_for(pattern, previous, fresh, now),
            linked_signal_ids: attrs[:linked_signal_ids],
            departments: canonical_departments(attrs[:departments]),
            last_updated_at: now,
            status: fresh >= 0.75 ? "confirmed" : "emerging"
          )

          # A pattern going backwards is the case this change makes possible, so
          # it is worth being able to see in the logs rather than only in the
          # history column.
          if fresh < previous - CONFIDENCE_MOVE
            Rails.logger.info(
              "[PatternUpsert] company=#{@company.id} pattern=#{pattern.id} " \
              "confidence #{previous.round(2)} -> #{fresh.round(2)} (#{pattern.title})"
            )
          end
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

    # Below this, a confidence change is recomputation noise rather than a real
    # move, and recording it would bury the real ones. Matches the 0.05 band
    # SignalUpsertService uses for strength_history.
    CONFIDENCE_MOVE = 0.05

    # Capped so a company re-aggregating for years does not grow an unbounded
    # jsonb column.
    MAX_HISTORY = 40

    def history_for(pattern, previous, fresh, now)
      history = Array(pattern.confidence_history)
      return history if (fresh - previous).abs <= CONFIDENCE_MOVE

      (history + [{ "confidence" => previous, "at" => now.iso8601 }]).last(MAX_HISTORY)
    end

    # Dedupe departments case-insensitively (keeping first-seen casing).
    def canonical_departments(list)
      Array(list).map { |d| d.to_s.strip }.reject(&:blank?).each_with_object({}) do |dept, acc|
        acc[dept.downcase] ||= dept
      end.values
    end
  end
end
