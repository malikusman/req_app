# frozen_string_literal: true

module ConsultantAssignments
  class AssignService
    MAX_ACTIVE = 2

    def self.call(company:, consultant_user:, platform_user:, request: nil)
      new(company: company, consultant_user: consultant_user, platform_user: platform_user, request: request).call
    end

    def initialize(company:, consultant_user:, platform_user:, request: nil)
      @company = company
      @consultant_user = consultant_user
      @platform_user = platform_user
      @request = request
    end

    def call
      active_count = @company.consultant_assignments.active.count
      raise ArgumentError, "Maximum #{MAX_ACTIVE} consultants per company" if active_count >= MAX_ACTIVE

      if @company.consultant_assignments.active.exists?(consultant_user_id: @consultant_user.id)
        raise ArgumentError, "Consultant already assigned"
      end

      assignment = ConsultantAssignment.create!(
        company: @company,
        consultant_user: @consultant_user,
        assigned_by_platform_user: @platform_user,
        status: "active",
        assigned_at: Time.current
      )

      PlatformAuditService.log!(
        platform_user: @platform_user,
        action: "consultant_assigned",
        target: @company,
        metadata: { consultant_user_id: @consultant_user.id },
        request: @request
      )

      NotificationService.notify_consultant_assigned(consultant: @consultant_user, company: @company)
      backfill_review!
      assignment
    end

    private

    # A consultant assigned AFTER a report was generated previously got no review
    # task and didn't block approval. Backfill a review for the latest
    # not-yet-approved ready report and re-open the gate so it can't be approved
    # until this consultant submits.
    def backfill_review!
      report = @company.reports.ready
                       .where.not(review_workflow_status: "platform_approved")
                       .order(version: :desc).first
      return unless report

      review = ReportReview.find_or_create_by!(report: report, consultant_user: @consultant_user) do |r|
        r.company = @company
        r.status = "pending"
      end
      ReportSections::KEYS.each do |key|
        review.report_review_section_states.find_or_create_by!(section_key: key)
      end

      if report.review_workflow_status == "reviews_complete"
        report.update!(review_workflow_status: "awaiting_consultants", visibility: "internal_only")
      end

      NotificationService.notify_consultant_report_ready(consultant: @consultant_user, company: @company, report: report)
    rescue StandardError => e
      Rails.logger.warn("[AssignService] backfill_review skipped: #{e.class}: #{e.message}")
    end
  end
end
