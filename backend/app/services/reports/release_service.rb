# frozen_string_literal: true

module Reports
  class ReleaseService
    def self.call(report:, platform_user:, request: nil)
      new(report: report, platform_user: platform_user, request: request).call
    end

    def initialize(report:, platform_user:, request: nil)
      @report = report
      @company = report.company
      @platform_user = platform_user
      @request = request
    end

    def call
      raise ArgumentError, "Report is not ready" unless @report.status == "ready"

      if reviewers_assigned? && !skip_reviewer_gate?
        unless @report.review_workflow_status == "reviews_complete"
          raise ArgumentError, "All reviewer sign-offs required before release"
        end
      end

      if @report.review_workflow_status.in?(%w[awaiting_reviewers in_review])
        raise ArgumentError, "Reviewer reviews are still in progress"
      end

      @report.update!(
        visibility: "shared_with_company",
        review_workflow_status: "platform_approved",
        reviewed_by_platform_user: @platform_user,
        reviewed_at: Time.current
      )

      PlatformAuditService.log!(
        platform_user: @platform_user,
        action: "report_released",
        target: @report,
        metadata: { company_id: @company.id, version: @report.version },
        request: @request
      )

      @report
    end

    private

    def reviewers_assigned?
      @company.reviewer_assignments.active.exists?
    end

    def skip_reviewer_gate?
      @company.merged_settings["skip_platform_review"] == true
    end
  end
end
