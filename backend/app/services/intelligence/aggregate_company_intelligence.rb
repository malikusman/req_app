# frozen_string_literal: true

module Intelligence
  class AggregateCompanyIntelligence
    def self.call(company:, department: nil)
      new(company: company, department: department).call
    end

    def initialize(company:, department: nil)
      @company = company
      @department = department
    end

    def call
      signals = SignalExtractor.call(company: @company)
      # Full-company runs reconcile (replace counts, drop stale). Department-scoped jobs only upsert.
      SignalUpsertService.call(
        company: @company,
        signals: signals,
        department: @department,
        reconcile_stale: @department.blank?
      )

      patterns = PatternDetector.call(company: @company)
      PatternUpsertService.call(company: @company, patterns: patterns)

      recommendations = RecommendationSynthesizer.call(company: @company)
      RecommendationUpsertService.call(company: @company, recommendations: recommendations)

      confirmed_patterns = @company.patterns.where(status: "confirmed").count
      @company.update!(
        report_readiness_breakdown: @company.report_readiness_breakdown.merge(
          "confirmed_patterns" => confirmed_patterns
        ),
        intelligence_snapshot: SnapshotBuilder.call(company: @company.reload)
      )

      CompanyReadinessRefresher.call(@company)
      NotificationService.notify_pattern_detected(company: @company) if patterns.any?

      { signals: signals.size, patterns: patterns.size, recommendations: recommendations.size }
    end
  end
end
