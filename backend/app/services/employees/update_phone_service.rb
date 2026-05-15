# frozen_string_literal: true

module Employees
  class UpdatePhoneService
    def self.call(employee:, new_phone_e164:, changed_by:)
      new(employee: employee, new_phone_e164: new_phone_e164, changed_by: changed_by).call
    end

    def initialize(employee:, new_phone_e164:, changed_by:)
      @employee = employee
      @new_phone = PhoneNormalizer.call(new_phone_e164)
      @changed_by = changed_by
    end

    def call
      if Employee.where.not(id: @employee.id).exists?(phone_e164: @new_phone)
        raise ArgumentError, "Phone number already in use"
      end

      ActiveRecord::Base.transaction do
        metadata = @employee.metadata
        metadata["previous_phones"] ||= []
        metadata["previous_phones"] << {
          "phone_e164" => @employee.phone_e164,
          "changed_at" => Time.current.iso8601,
          "changed_by_id" => @changed_by.id
        }

        @employee.employee_access_codes.active.update_all(status: "revoked", revoked_at: Time.current)
        _code, plain_code = EmployeeAccessCode.issue_for!(
          employee: @employee,
          issued_by_type: "company_user"
        )

        @employee.update!(phone_e164: @new_phone, metadata: metadata)

        { employee: @employee.reload, access_code: plain_code }
      end
    end
  end
end
