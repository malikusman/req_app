# frozen_string_literal: true

module AccessCodes
  class RotateAllService
    def self.call(company:, rotated_by: nil)
      new(company: company, rotated_by: rotated_by).call
    end

    def initialize(company:, rotated_by: nil)
      @company = company
      @rotated_by = rotated_by
    end

    def call
      count = 0
      @company.employees.find_each do |employee|
        employee.employee_access_codes.active.update_all(status: "revoked", revoked_at: Time.current)
        EmployeeAccessCode.issue_for!(employee: employee, issued_by_type: "rotation")
        count += 1
      end
      count
    end
  end
end
