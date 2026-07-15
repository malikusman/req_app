# frozen_string_literal: true

module EmployeeValue
  class SendDigestService
    def self.call(digest:)
      new(digest: digest).call
    end

    def initialize(digest:)
      @digest = digest
    end

    def call
      employee = @digest.employee
      raise ArgumentError, "Employee has no email" if employee.email.blank?

      preference = employee.try(:employee_value_preference) ||
                   EmployeeValuePreference.find_by(employee_id: employee.id)
      if preference && !preference.subscribed?
        raise ArgumentError, "Employee is not opted in to value digests"
      end

      DigestsMailer.digest_email(@digest).deliver_later

      @digest.update!(
        status: "sent",
        sent_at: Time.current,
        delivery_status: "sent"
      )
      @digest
    rescue StandardError => e
      @digest.update!(delivery_status: "failed", status: @digest.status == "sent" ? "sent" : "failed")
      raise
    end
  end
end
