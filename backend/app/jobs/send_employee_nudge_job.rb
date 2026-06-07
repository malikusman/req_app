# frozen_string_literal: true

class SendEmployeeNudgeJob < ApplicationJob
  queue_as :default

  NUDGE_COOLDOWN = 24.hours

  def perform(employee_id, company_user_id)
    employee = Employee.find(employee_id)
    company_user = CompanyUser.find(company_user_id)
    nudge_created = false

    employee.with_lock do
      employee.reload

      if duplicate_nudge?(employee)
        Rails.logger.info("[SendEmployeeNudgeJob] skip duplicate employee=#{employee_id}")
        return
      end

      response = send_whatsapp!(employee)
      meta_id = response.dig("messages", 0, "id")

      EmployeeNudge.create!(
        employee: employee,
        company_user: company_user,
        conversation: employee.conversations.order(updated_at: :desc).first,
        meta_message_id: meta_id,
        sent_at: Time.current
      )
      nudge_created = true

      employee.update!(last_nudged_at: Time.current)
    end
  rescue StandardError => e
    restore_last_nudged_at!(employee_id) unless nudge_created
    raise e
  end

  private

  def duplicate_nudge?(employee)
    employee.employee_nudges.where("sent_at > ?", NUDGE_COOLDOWN.ago).exists?
  end

  def send_whatsapp!(employee)
    client = Whatsapp::MetaClient.new
    company = employee.company

    if client.configured?
      client.send_nudge_template(
        to: employee.phone_e164,
        employee_name: employee.display_name,
        company_name: company.display_name || company.name
      )
    else
      Rails.logger.info("[WhatsApp dev nudge] employee=#{employee.id}")
      { "messages" => [{ "id" => "dev-#{SecureRandom.hex(8)}" }] }
    end
  end

  def restore_last_nudged_at!(employee_id)
    employee = Employee.find_by(id: employee_id)
    return unless employee

    last_sent = employee.employee_nudges.maximum(:sent_at)
    employee.update!(last_nudged_at: last_sent)
  end
end
