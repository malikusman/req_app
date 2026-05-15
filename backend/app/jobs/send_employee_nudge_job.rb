# frozen_string_literal: true

class SendEmployeeNudgeJob < ApplicationJob
  queue_as :default

  NUDGE_COOLDOWN = 24.hours

  def perform(employee_id, company_user_id)
    employee = Employee.find(employee_id)
    company_user = CompanyUser.find(company_user_id)

    if employee.last_nudged_at.present? && employee.last_nudged_at > NUDGE_COOLDOWN.ago
      raise StandardError, "Nudge cooldown active"
    end

    client = Whatsapp::MetaClient.new
    company = employee.company

    response = if client.configured?
                 client.send_nudge_template(
                   to: employee.phone_e164,
                   employee_name: employee.display_name,
                   company_name: company.display_name || company.name
                 )
               else
                 Rails.logger.info("[WhatsApp dev nudge] employee=#{employee.id}")
                 { "messages" => [{ "id" => "dev-#{SecureRandom.hex(8)}" }] }
               end

    meta_id = response.dig("messages", 0, "id")
    nudge = EmployeeNudge.create!(
      employee: employee,
      company_user: company_user,
      conversation: employee.conversations.order(updated_at: :desc).first,
      meta_message_id: meta_id,
      sent_at: Time.current
    )

    employee.update!(last_nudged_at: Time.current)
    nudge
  end
end
