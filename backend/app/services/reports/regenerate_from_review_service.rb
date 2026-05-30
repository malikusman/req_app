# frozen_string_literal: true

module Reports
  class RegenerateFromReviewService
    def self.call(source_report:, requested_by:, note: nil)
      new(source_report: source_report, requested_by: requested_by, note: note).call
    end

    def initialize(source_report:, requested_by:, note: nil)
      @source_report = source_report
      @company = source_report.company
      @requested_by = requested_by
      @note = note
    end

    def call
      report = @company.reports.create!(
        version: (@company.reports.maximum(:version) || 0) + 1,
        status: "queued",
        visibility: "internal_only",
        review_workflow_status: "not_required",
        triggered_by_type: @requested_by.class.name,
        triggered_by_id: @requested_by.id,
        previous_report: @company.reports.ready.order(version: :desc).first,
        regeneration_source_report: @source_report,
        regeneration_note: @note
      )

      GenerateReportJob.perform_later(report.id)
      report
    end
  end
end
