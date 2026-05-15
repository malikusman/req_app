# frozen_string_literal: true

class NotificationService
  def self.notify(type:, company:, recipients:, title:, body:, action_url: nil, metadata: {})
    recipients = Array(recipients)
    recipients.each do |recipient|
      notification = Notification.create!(
        company: company,
        recipient_type: recipient.class.name,
        recipient_id: recipient.id,
        notification_type: type.to_s,
        title: title,
        body: body,
        action_url: action_url,
        metadata: metadata
      )

      broadcast_notification(recipient, notification)
      DeliverNotificationEmailJob.perform_later(recipient.class.name, recipient.id) if email_enabled?(recipient)
    end
  end

  def self.notify_interview_started(company:, employee:)
    admins = company.company_users.where(role: "company_admin", status: "active")
    notify(
      type: :employee_started,
      company: company,
      recipients: admins,
      title: "Employee started discovery",
      body: "#{employee.display_name || employee.phone_e164} began their WhatsApp conversation.",
      action_url: "#{app_host}/company/employees",
      metadata: { employee_id: employee.id }
    )
  end

  def self.notify_pattern_detected(company:)
    pattern = company.patterns.order(confidence: :desc).first
    return unless pattern

    admins = company.company_users.where(role: "company_admin", status: "active")
    notify(
      type: :pattern_detected,
      company: company,
      recipients: admins,
      title: "New pattern detected",
      body: pattern.title,
      action_url: "#{app_host}/company/intelligence/timeline",
      metadata: { pattern_id: pattern.id }
    )
  end

  def self.notify_report_ready(company:, report:)
    admins = company.company_users.where(role: "company_admin", status: "active")
    notify(
      type: :report_ready,
      company: company,
      recipients: admins,
      title: "Report ready",
      body: "Your workflow discovery report v#{report.version} is ready to download.",
      action_url: "#{app_host}/company/reports/#{report.id}",
      metadata: { report_id: report.id, version: report.version }
    )
  end

  def self.notify_report_shared(company:, report:)
    admins = company.company_users.where(role: "company_admin", status: "active")
    notify(
      type: :report_shared,
      company: company,
      recipients: admins,
      title: "Report share link created",
      body: "Share link for report v#{report.version} expires #{report.share_token_expires_at&.strftime('%b %d, %Y')}.",
      action_url: "#{app_host}/company/reports/#{report.id}",
      metadata: { report_id: report.id }
    )
  end

  def self.notify_interview_completed(company:, employee:)
    admins = company.company_users.where(role: "company_admin", status: "active")
    notify(
      type: :interview_completed,
      company: company,
      recipients: admins,
      title: "Interview completed",
      body: "#{employee.display_name || employee.phone_e164} completed their discovery conversation.",
      action_url: "#{app_host}/company/employees/#{employee.id}",
      metadata: { employee_id: employee.id }
    )
  end

  def self.email_enabled?(recipient)
    prefs = recipient.try(:notification_preferences) || {}
    prefs["email_enabled"] != false
  end

  def self.app_host
    ENV.fetch("APP_HOST", "http://localhost:5173")
  end

  def self.broadcast_notification(recipient, notification)
    unread_count = Notification.where(recipient: recipient).unread.count
    CompanyNotificationsChannel.broadcast_to(
      recipient,
      {
        type: "notification",
        unread_count: unread_count,
        notification: {
          id: notification.id,
          notification_type: notification.notification_type,
          title: notification.title,
          body: notification.body,
          action_url: notification.action_url,
          created_at: notification.created_at
        }
      }
    )
  rescue StandardError => e
    Rails.logger.warn("[NotificationService] ActionCable broadcast failed: #{e.message}")
  end
end
