# frozen_string_literal: true

module ConsultantAssignments
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
        action: "consultant_removed",
        target: @assignment.company,
        metadata: { consultant_user_id: @assignment.consultant_user_id },
        request: @request
      )

      @assignment
    end
  end
end
