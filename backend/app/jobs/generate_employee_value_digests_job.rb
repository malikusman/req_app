# frozen_string_literal: true

class GenerateEmployeeValueDigestsJob < ApplicationJob
  queue_as :default

  def perform(period_key = nil)
    period = period_key.presence || Time.current.utc.strftime("%Y-%m")

    EmployeeValuePreference.opted_in.find_each do |preference|
      next unless due?(preference)

      digest = EmployeeValue::GenerateDigestService.call(employee: preference.employee, period_key: period)
      next if digest.status == "sent"

      # Pilot mode: mark reviewed then send. Skip employees without email.
      if preference.employee.email.present?
        digest.update!(status: "reviewed") if digest.status == "draft"
        EmployeeValue::SendDigestService.call(digest: digest)
      else
        digest.update!(status: "suppressed", delivery_status: "no_email")
      end
    rescue StandardError => e
      Rails.logger.error(
        "[GenerateEmployeeValueDigestsJob] employee=#{preference.employee_id} failed: #{e.message}"
      )
    end
  end

  private

  def due?(preference)
    case preference.frequency
    when "twice_monthly"
      day = Time.current.day
      day <= 2 || (day >= 15 && day <= 17)
    else
      Time.current.day <= 3
    end
  end
end
