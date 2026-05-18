# frozen_string_literal: true

module ReportReviews
  class BootstrapService
    def self.call(report:)
      new(report: report).call
    end

    def initialize(report:)
      @report = report
      @company = report.company
    end

    def call
      assignments = @company.reviewer_assignments.active.includes(:reviewer_user)
      return if assignments.empty?

      @report.update!(
        review_workflow_status: "awaiting_reviewers",
        visibility: "internal_only"
      )

      assignments.each do |assignment|
        review = ReportReview.find_or_create_by!(
          report: @report,
          reviewer_user: assignment.reviewer_user
        ) do |r|
          r.company = @company
          r.status = "pending"
        end

        ReportSections::KEYS.each do |key|
          review.report_review_section_states.find_or_create_by!(section_key: key)
        end

        NotificationService.notify_reviewer_report_ready(
          reviewer: assignment.reviewer_user,
          company: @company,
          report: @report
        )
      end
    end
  end
end
