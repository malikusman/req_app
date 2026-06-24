# frozen_string_literal: true

module Employees
  module NudgeEligibility
    module_function

    def can_nudge?(employee)
      employee.participation_status == "started" && !cooldown_active?(employee)
    end

    def cooldown_active?(employee)
      return true if employee.last_nudged_at.present? &&
                     employee.last_nudged_at > SendEmployeeNudgeJob::NUDGE_COOLDOWN.ago

      employee.employee_nudges
              .where(delivery_status: %w[sent partial])
              .where("sent_at > ?", SendEmployeeNudgeJob::NUDGE_COOLDOWN.ago)
              .exists?
    end
  end
end
