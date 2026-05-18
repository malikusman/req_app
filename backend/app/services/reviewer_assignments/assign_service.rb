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
      assignment
    end
  end
end
