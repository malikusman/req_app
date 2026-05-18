# frozen_string_literal: true

module Reports
  class SnapshotBuilder
    def self.call(company:, delta:)
      new(company: company, delta: delta).call
    end

    def initialize(company:, delta:)
      @company = company
      @delta = delta
    end

    def call
      {
        "generated_at" => Time.current.iso8601,
        "company" => {
          "name" => @company.display_name || @company.name,
          "locale" => @company.locale
        },
        "readiness" => {
          "score" => @company.report_readiness_score,
          "breakdown" => @company.report_readiness_breakdown
        },
        "participation" => Intelligence::SnapshotBuilder.call(company: @company)["participation"],
        "signals" => @company.company_signals.order(strength: :desc).map do |s|
          { "id" => s.id, "label" => s.label, "strength" => s.strength, "departments" => s.departments, "signal_type" => s.signal_type }
        end,
        "patterns" => @company.patterns.order(confidence: :desc).map do |p|
          { "id" => p.id, "title" => p.title, "description" => p.description, "confidence" => p.confidence }
        end,
        "recommendations" => @company.recommendations.published.visible_to_company.map do |r|
          {
            "id" => r.id,
            "title" => r.title,
            "description" => r.description,
            "implementation_outline" => r.implementation_outline,
            "catalog_matches" => r.catalog_matches,
            "priority" => r.priority
          }
        end,
        "delta_from_previous" => @delta,
        "sections" => ReportSections::DEFINITIONS
      }
    end
  end
end
