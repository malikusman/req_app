# frozen_string_literal: true

module ReviewerAssignments
  class AssignService
    MAX_ACTIVE = 2

    def self.call(company:, reviewer_user:, platform_user:, request: nil)
      new(company: company, reviewer_user: reviewer_user, platform_user: platform_user, request: request).call
    end

    def initialize(company:, reviewer_user:, platform_user:, request: nil)
      @company = company
      @reviewer_user = reviewer_user
      @platform_user = platform_user
      @request = request
    end

    def call
      active_count = @company.reviewer_assignments.active.count
      raise ArgumentError, "Maximum #{MAX_ACTIVE} reviewers per company" if active_count >= MAX_ACTIVE

      if @company.reviewer_assignments.active.exists?(reviewer_user_id: @reviewer_user.id)
        raise ArgumentError, "Reviewer already assigned"
      end

      assignment = ReviewerAssignment.create!(
        company: @company,
        reviewer_user: @reviewer_user,
        assigned_by_platform_user: @platform_user,
        status: "active",
        assigned_at: Time.current
      )

      PlatformAuditService.log!(
        platform_user: @platform_user,
        action: "reviewer_assigned",
        target: @company,
        metadata: { reviewer_user_id: @reviewer_user.id },
        request: @request
      )

      NotificationService.notify_reviewer_assigned(reviewer: @reviewer_user, company: @company)
      backfill_review!
      assignment
    end

    private

    # A reviewer assigned AFTER a report was generated previously got no review
    # task and didn't block approval. Backfill a review for the latest
    # not-yet-approved ready report and re-open the gate so it can't be approved
    # until this reviewer submits.
    def backfill_review!
      report = @company.reports.ready
                       .where.not(review_workflow_status: "platform_approved")
                       .order(version: :desc).first
      return unless report

      review = ReportReview.find_or_create_by!(report: report, reviewer_user: @reviewer_user) do |r|
        r.company = @company
        r.status = "pending"
      end
      ReportSections::KEYS.each do |key|
        review.report_review_section_states.find_or_create_by!(section_key: key)
      end

      if report.review_workflow_status == "reviews_complete"
        report.update!(review_workflow_status: "awaiting_reviewers", visibility: "internal_only")
      end

      NotificationService.notify_reviewer_report_ready(reviewer: @reviewer_user, company: @company, report: report)
    rescue StandardError => e
      Rails.logger.warn("[AssignService] backfill_review skipped: #{e.class}: #{e.message}")
    end
  end
end
