# frozen_string_literal: true

class SendEmployeeNudgeJob < ApplicationJob
  queue_as :default

  NUDGE_COOLDOWN = 24.hours

  discard_on ActiveRecord::RecordNotFound do |job, error|
    Rails.logger.warn(
      "[SendEmployeeNudgeJob] discarding job #{job.job_id}: #{error.message} args=#{job.arguments.inspect}"
    )
  end

  def perform(employee_nudge_id)
    nudge = EmployeeNudge.find(employee_nudge_id)
    deliver!(nudge)
  rescue StandardError => e
    mark_failed!(nudge, e.message) if defined?(nudge) && nudge.is_a?(EmployeeNudge)
    raise
  end

  def self.requeue_stuck!(older_than: 2.minutes)
    scope = EmployeeNudge.where(delivery_status: "queued", whatsapp_status: "queued")
                         .where("created_at < ?", older_than.ago)

    scope.find_each do |nudge|
      perform_later(nudge.id)
    end
  end

  def self.backfill_legacy_statuses!
    EmployeeNudge.where(delivery_status: "queued")
                 .where.not(meta_message_id: nil)
                 .update_all(delivery_status: "sent", whatsapp_status: "sent", updated_at: Time.current)

    EmployeeNudge.where(delivery_status: "queued", whatsapp_status: nil, meta_message_id: nil)
                 .where("created_at < ?", 1.hour.ago)
                 .update_all(
                   delivery_status: "failed",
                   whatsapp_status: "failed",
                   error_message: "Nudge was not delivered (legacy record)",
                   updated_at: Time.current
                 )
  end

  private

  def deliver!(nudge)
    employee = nudge.employee
    company = employee.company
    errors = []
    whatsapp_ok = false
    email_ok = false
    meta_id = nudge.meta_message_id

    if nudge.whatsapp_channel?
      whatsapp_ok, meta_id, wa_error = deliver_whatsapp!(employee, company)
      errors << wa_error if wa_error.present?
    else
      nudge.update!(whatsapp_status: "skipped")
    end

    if nudge.email_channel? && employee.email.present?
      email_ok, email_error = deliver_email!(employee, company)
      errors << email_error if email_error.present?
    elsif nudge.email_channel?
      nudge.update!(email_status: "skipped")
      errors << "Email: no address on file"
    end

    delivery_status = derive_delivery_status(whatsapp_ok: whatsapp_ok, email_ok: email_ok, nudge: nudge)

    nudge.update!(
      delivery_status: delivery_status,
      whatsapp_status: whatsapp_status_for(whatsapp_ok, nudge),
      email_status: email_status_for(email_ok, nudge, employee),
      meta_message_id: meta_id,
      error_message: errors.join("; ").presence
    )

    employee.update!(last_nudged_at: Time.current) if delivery_status.in?(%w[sent partial])
  end

  def mark_failed!(nudge, message)
    nudge.update!(
      delivery_status: "failed",
      whatsapp_status: nudge.whatsapp_channel? ? "failed" : nudge.whatsapp_status,
      email_status: nudge.email_channel? ? "failed" : nudge.email_status,
      error_message: message
    )
  rescue StandardError => e
    Rails.logger.error("[SendEmployeeNudgeJob] could not mark nudge #{nudge.id} failed: #{e.message}")
  end

  def deliver_whatsapp!(employee, company)
    client = Whatsapp::MetaClient.new

    unless client.configured?
      Rails.logger.info("[WhatsApp dev nudge] employee=#{employee.id}")
      WhatsappDeliveryMetric.record!("template_sent", metadata: { employee_id: employee.id, dev: true })
      return [true, "dev-#{SecureRandom.hex(8)}", nil]
    end

    response = client.send_nudge_template(
      to: employee.phone_e164,
      employee_name: employee.display_name,
      company_name: company.display_name || company.name
    )
    meta_id = response.dig("messages", 0, "id")
    WhatsappDeliveryMetric.record!("template_sent", metadata: { employee_id: employee.id, meta_message_id: meta_id })
    [true, meta_id, nil]
  rescue Whatsapp::MetaClient::ApiError => e
    WhatsappDeliveryMetric.record!("template_failed", metadata: { employee_id: employee.id, error: e.message })
    [false, nil, "WhatsApp: #{e.message}"]
  end

  def deliver_email!(employee, company)
    EmployeeNudgeMailer.nudge_email(employee: employee, company: company).deliver_now
    [true, nil]
  rescue StandardError => e
    [false, "Email: #{e.message}"]
  end

  def derive_delivery_status(whatsapp_ok:, email_ok:, nudge:)
    wants_wa = nudge.whatsapp_channel?
    wants_email = nudge.email_channel? && nudge.employee.email.present?

    wa_result = wants_wa ? whatsapp_ok : true
    email_result = wants_email ? email_ok : true

    if wa_result && email_result
      "sent"
    elsif whatsapp_ok || email_ok
      "partial"
    else
      "failed"
    end
  end

  def whatsapp_status_for(whatsapp_ok, nudge)
    return "skipped" unless nudge.whatsapp_channel?

    whatsapp_ok ? "sent" : "failed"
  end

  def email_status_for(email_ok, nudge, employee)
    return "skipped" unless nudge.email_channel?

    employee.email.blank? ? "skipped" : (email_ok ? "sent" : "failed")
  end
end
