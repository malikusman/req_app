# frozen_string_literal: true

module ReviewerAssignments
  class RemoveService
    def self.call(assignment:, platform_user:, request: nil)
      new(assignment: assignment, platform_user: platform_user, request: request).call
    end

    def initialize(assignment:, platform_user:, request: nil)
      @assignment = assignment
      @platform_user = platform_user
      @request = request
    end

    def call
      @assignment.remove!

      PlatformAuditService.log!(
        platform_user: @platform_user,
        action: "reviewer_removed",
        target: @assignment.company,
        metadata: { reviewer_user_id: @assignment.reviewer_user_id },
        request: @request
      )

      @assignment
    end
  end
end
