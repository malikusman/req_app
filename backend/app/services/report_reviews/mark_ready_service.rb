# frozen_string_literal: true

module ReportReviews
  class MarkReadyService
    def self.call(report_review:, note: nil)
      new(report_review: report_review, note: note).call
    end

    def initialize(report_review:, note: nil)
      @report_review = report_review
      @note = note
    end

    def call
      raise ArgumentError, "Review already submitted" if @report_review.submitted?

      @report_review.mark_ready!(note: @note)

      report = @report_review.report
      report.update!(review_workflow_status: "in_review") if report.review_workflow_status == "awaiting_reviewers"

      @report_review
    end
  end
end
