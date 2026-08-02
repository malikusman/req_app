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

      stack_count = infer_stack!
      catalog_matches = rematch_catalog!
      idea_count = synthesize_agentic_ideas!

      confirmed_patterns = @company.patterns.where(status: "confirmed").count
      @company.update!(
        report_readiness_breakdown: @company.report_readiness_breakdown.merge(
          "confirmed_patterns" => confirmed_patterns
        ),
        intelligence_snapshot: SnapshotBuilder.call(company: @company.reload),
        intelligence_updated_at: Time.current
      )

      CompanyReadinessRefresher.call(@company)
      TimelineRecorder.intelligence_refreshed!(
        company: @company,
        summary: "Updated #{signals.size} signals, #{patterns.size} patterns, #{recommendations.size} recommendations"
      )
      NotificationService.notify_pattern_detected(company: @company) if patterns.any?

      {
        signals: signals.size,
        patterns: patterns.size,
        recommendations: recommendations.size,
        catalog_matches: catalog_matches,
        company_systems: stack_count,
        agentic_ideas: idea_count
      }
    end

    private

    def infer_stack!
      return 0 unless defined?(Intelligence::CompanyStackInferrer)

      Array(Intelligence::CompanyStackInferrer.call(company: @company)).size
    rescue StandardError => e
      Rails.logger.warn("[AggregateCompanyIntelligence] stack infer failed company=#{@company.id}: #{e.message}")
      0
    end

    def rematch_catalog!
      return 0 unless defined?(Catalog::CompanyFitService)

      matches = Catalog::CompanyFitService.call(company: @company.reload)
      Array(matches).size
    rescue StandardError => e
      Rails.logger.warn("[AggregateCompanyIntelligence] catalog rematch failed company=#{@company.id}: #{e.message}")
      0
    end

    def synthesize_agentic_ideas!
      return 0 unless defined?(Intelligence::AgenticIdeaSynthesizer)

      company = @company.reload
      # Prefer LLM-written, company-specific ideas; fall back to the deterministic
      # rule-based synthesizer when the model is unavailable or returns nothing.
      ideas = (defined?(Intelligence::AgenticIdeaWriter) && Intelligence::AgenticIdeaWriter.call(company: company)) ||
              Intelligence::AgenticIdeaSynthesizer.call(company: company)
      Array(Intelligence::AgenticIdeaUpsertService.call(company: @company, ideas: ideas)).size
    rescue StandardError => e
      Rails.logger.warn("[AggregateCompanyIntelligence] agentic ideas failed company=#{@company.id}: #{e.message}")
      0
    end
  end
end
