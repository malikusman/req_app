# frozen_string_literal: true

module ReportReviews
  class SubmitService
    class IncompleteReviewError < ArgumentError; end

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

      validate_completeness!

      status = needs_info? ? "needs_info" : "approved"
      @report_review.update!(submitted_at: Time.current, status: status)

      NotificationService.notify_review_submitted(report: @report, consultant: @report_review.consultant_user)

      check_all_submitted!
      @report_review
    end

    private

    def validate_completeness!
      states = @report_review.report_review_section_states.index_by(&:section_key)
      incomplete = ReportSections::KEYS.reject do |key|
        state = states[key]
        state && state.status.in?(%w[approved needs_info])
      end
      if incomplete.any?
        raise IncompleteReviewError,
              "All sections must be approved or needs_info before submit (pending: #{incomplete.join(', ')})"
      end

      if @report_review.overall_note.to_s.strip.blank?
        raise IncompleteReviewError, "Overall conclusion is required before submit"
      end

      needs_info_keys = ReportSections::KEYS.select { |key| states[key]&.status == "needs_info" }
      needs_info_keys.each do |key|
        has_comment = @report_review.report_review_comments.where(section_key: key).exists?
        next if has_comment

        raise IncompleteReviewError,
              "Section #{key} marked needs_info requires an explanatory comment"
      end

      return unless defined?(ReportReviewFinding) && ReportReviewFinding.table_exists?

      findings = @report_review.report_review_findings
      unless findings.where(finding_type: "executive_conclusion", publishable: true).exists?
        raise IncompleteReviewError, "A publishable executive conclusion finding is required"
      end
    end

    def needs_info?
      @report_review.report_review_section_states.any? { |s| s.status == "needs_info" }
    end

    def check_all_submitted!
      active_consultant_ids = @company.consultant_assignments.active.pluck(:consultant_user_id)
      return if active_consultant_ids.empty?

      reviews = @report.report_reviews.where(consultant_user_id: active_consultant_ids)
      return unless reviews.all?(&:submitted?)

      @report.update!(
        review_workflow_status: "reviews_complete",
        reviews_completed_at: Time.current
      )

      NotificationService.notify_all_reviews_submitted(report: @report, company: @company)
    end
  end
end
