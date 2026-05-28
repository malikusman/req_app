# frozen_string_literal: true

module ReportReviews
  class AddReviewerToReportService
    def self.call(report:, reviewer_user:)
      new(report: report, reviewer_user: reviewer_user).call
    end

    def initialize(report:, reviewer_user:)
      @report = report
      @reviewer_user = reviewer_user
      @company = report.company
    end

    def call
      return unless @report.status == "ready"

      review = ReportReview.find_or_create_by!(report: @report, reviewer_user: @reviewer_user) do |r|
        r.company = @company
        r.status = "pending"
      end

      ReportSections::KEYS.each do |key|
        review.report_review_section_states.find_or_create_by!(section_key: key)
      end

      if @report.review_workflow_status.in?(%w[reviews_complete platform_approved not_required])
        @report.update!(
          review_workflow_status: "in_review",
          visibility: "internal_only",
          reviews_completed_at: nil
        )
      elsif @report.review_workflow_status == "not_required"
        @report.update!(review_workflow_status: "awaiting_reviewers", visibility: "internal_only")
      end

      NotificationService.notify_reviewer_report_ready(
        reviewer: @reviewer_user,
        company: @company,
        report: @report
      )

      review
    end
  end
end
