# frozen_string_literal: true

class ReportReadinessCalculator
  # Interview-led scoring (employees present).
  INTERVIEW_WEIGHTS = { employees: 30, departments: 30, patterns: 25, multimodal: 15 }.freeze

  # Docs-first scoring when no completed interviews yet.
  DOCS_WEIGHTS = { ready_documents: 40, document_departments: 20, patterns: 25, multimodal: 15 }.freeze

  def self.call(company)
    new(company).call
  end

  def initialize(company)
    @company = company
    @breakdown = company.report_readiness_breakdown || {}
    @thresholds = company.merged_settings.fetch("report_thresholds", {})
    @mode = company.merged_settings["engagement_mode"].presence || "hybrid"
  end

  def call
    composite = if pure_docs_phase?
                  weighted_score(DOCS_WEIGHTS)
                else
                  blended_score
                end

    @company.update!(report_readiness_score: composite)
    composite
  end

  # True when no completed interviews — baseline/docs narrative and DOCS_WEIGHTS only.
  def docs_phase?
    pure_docs_phase?
  end

  def pure_docs_phase?
    @breakdown["employees_interviewed"].to_i.zero?
  end

  def interview_blend
    return 0.0 if pure_docs_phase?

    min_emp = threshold("min_employees_interviewed", 3)
    return 1.0 if min_emp <= 0

    interviewed = @breakdown["employees_interviewed"].to_i
    [interviewed.to_f / min_emp, 1.0].min
  end

  private

  def blended_score
    docs = weighted_score(DOCS_WEIGHTS)
    interview = weighted_score(INTERVIEW_WEIGHTS)
    blend = interview_blend
    ((docs * (1.0 - blend)) + (interview * blend)).round(1)
  end

  def weighted_score(weights)
    scores = weights.keys.index_with { |key| dimension_score(key) }
    weights.sum { |key, weight| scores[key] * weight }.round(1)
  end

  def dimension_score(key)
    case key
    when :employees
      ratio(@breakdown["employees_interviewed"], threshold("min_employees_interviewed", 3))
    when :departments
      ratio(@breakdown["departments_represented"], threshold("min_departments", 2))
    when :patterns
      ratio(@breakdown["confirmed_patterns"], threshold("min_patterns", 1))
    when :multimodal
      ratio(@breakdown["multimodal_contributions"], threshold("min_multimodal_contributions", 1))
    when :ready_documents
      ratio(@breakdown["ready_documents"], threshold("min_ready_documents", 3))
    when :document_departments
      ratio(@breakdown["document_departments"], threshold("min_document_departments", 1))
    else
      0.0
    end
  end

  def threshold(name, default)
    value = @thresholds[name]
    value.nil? ? default : value.to_f
  end

  def ratio(actual, target)
    target = target.to_f
    return 0.0 if target <= 0

    [(actual.to_f / target), 1.0].min
  end
end
