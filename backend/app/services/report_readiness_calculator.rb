# frozen_string_literal: true

class ReportReadinessCalculator
  WEIGHTS = { employees: 30, departments: 30, patterns: 25, multimodal: 15 }.freeze

  def self.call(company)
    new(company).call
  end

  def initialize(company)
    @company = company
    @breakdown = company.report_readiness_breakdown
    @thresholds = company.merged_settings.fetch("report_thresholds", {})
  end

  def call
    scores = {
      employees: ratio(@breakdown["employees_interviewed"], @thresholds["min_employees_interviewed"]),
      departments: ratio(@breakdown["departments_represented"], @thresholds["min_departments"]),
      patterns: ratio(@breakdown["confirmed_patterns"], @thresholds["min_patterns"]),
      multimodal: ratio(@breakdown["multimodal_contributions"], @thresholds["min_multimodal_contributions"])
    }

    composite = WEIGHTS.sum { |key, weight| scores[key] * weight }.round(1)
    @company.update!(report_readiness_score: composite)
    composite
  end

  private

  def ratio(actual, target)
    target = target.to_f
    return 0.0 if target <= 0

    [(actual.to_f / target), 1.0].min
  end
end
