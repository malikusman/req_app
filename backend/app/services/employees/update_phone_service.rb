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

        @employee.update!(phone_e164: @new_phone, metadata: metadata)
        @employee.company.ensure_join_code!

        { employee: @employee.reload, company_join_code: @employee.company.join_code }
      end
    end
  end
end
