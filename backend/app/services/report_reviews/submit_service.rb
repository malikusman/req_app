# frozen_string_literal: true

module ReportReviews
  class SubmitService
    def self.call(report_review:)
      new(report_review: report_review).call
    end

    def initialize(report_review:)
      @report_review = report_review
      @report = report_review.report
      @company = report_review.company
    end

    def call
      raise ArgumentError, "Review already submitted" if @report_review.submitted?

      @report_review.submit!

      NotificationService.notify_review_submitted(report: @report, reviewer: @report_review.reviewer_user)

      check_all_submitted!
      @report_review
    end

    private

    def check_all_submitted!
      active_reviewer_ids = @company.reviewer_assignments.active.pluck(:reviewer_user_id)
      return if active_reviewer_ids.empty?

      reviews = @report.report_reviews.where(reviewer_user_id: active_reviewer_ids)
      return unless reviews.all?(&:submitted?)

      @report.update!(
        review_workflow_status: "reviews_complete",
        reviews_completed_at: Time.current
      )

      NotificationService.notify_all_reviews_submitted(report: @report, company: @company)
    end
  end
end
