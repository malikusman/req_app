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

  def self.notify_reviewer_assigned(reviewer:, company:)
    notify(
      type: :reviewer_assigned,
      company: company,
      recipients: reviewer,
      title: "New company assignment",
      body: "You have been assigned to review #{company.display_name || company.name}.",
      action_url: "#{app_host}/reviewer/companies/#{company.id}",
      metadata: { company_id: company.id }
    )
  end

  def self.notify_reviewer_report_ready(reviewer:, company:, report:)
    notify(
      type: :reviewer_report_ready,
      company: company,
      recipients: reviewer,
      title: "Report ready for review",
      body: "#{company.display_name || company.name} report v#{report.version} is ready.",
      action_url: "#{app_host}/reviewer/companies/#{company.id}/reports/#{report.id}",
      metadata: { report_id: report.id, company_id: company.id }
    )
  end

  def self.notify_co_reviewer_commented(reviewer:, company:, report:)
    notify(
      type: :co_reviewer_commented,
      company: company,
      recipients: reviewer,
      title: "Co-reviewer updated report",
      body: "Your co-reviewer added feedback on #{company.display_name || company.name} report v#{report.version}.",
      action_url: "#{app_host}/reviewer/companies/#{company.id}/reports/#{report.id}",
      metadata: { report_id: report.id }
    )
  end

  def self.notify_info_reply_received(reviewer:, request:, employee:)
    notify(
      type: :info_reply_received,
      company: request.company,
      recipients: reviewer,
      title: "Employee replied to follow-up",
      body: "#{employee.display_name || employee.phone_e164} replied to your clarification request.",
      action_url: "#{app_host}/reviewer/companies/#{request.company_id}/employees/#{employee.id}/followup",
      metadata: { request_id: request.id, employee_id: employee.id }
    )
  end

  def self.notify_review_submitted(report:, reviewer:)
    notify_platform_admins(
      type: :review_submitted,
      company: report.company,
      title: "Reviewer submitted report",
      body: "#{reviewer.name} submitted their review for report v#{report.version}.",
      action_url: "#{app_host}/platform/companies/#{report.company_id}/reports",
      metadata: { report_id: report.id, reviewer_user_id: reviewer.id }
    )
  end

  def self.notify_all_reviews_submitted(report:, company:)
    notify_platform_admins(
      type: :all_reviews_submitted,
      company: company,
      title: "All reviews submitted",
      body: "All assigned reviewers have submitted for report v#{report.version}. Ready for platform approval.",
      action_url: "#{app_host}/platform/companies/#{company.id}/reports",
      metadata: { report_id: report.id }
    )
  end

  def self.notify_reviewer_chat_message(recipient:, company:, sender:)
    notify(
      type: :reviewer_chat_message,
      company: company,
      recipients: recipient,
      title: "Message from co-reviewer",
      body: "#{sender.name} sent a message on #{company.display_name || company.name}.",
      action_url: "#{app_host}/reviewer/companies/#{company.id}/chat",
      metadata: { company_id: company.id }
    )
  end

  def self.notify_discussion_mention(recipient:, company:, report:, author:, discussion:)
    anchor = "#{discussion.anchor_type}:#{discussion.anchor_id}"
    notify(
      type: :discussion_mention,
      company: company,
      recipients: recipient,
      title: "Question from co-reviewer",
      body: "#{author.name} asked about #{discussion.anchor_type} on #{company.display_name || company.name} report v#{report.version}.",
      action_url: "#{app_host}/reviewer/companies/#{company.id}/reports/#{report.id}/review?step=evidence&anchor=#{anchor}",
      metadata: {
        report_id: report.id,
        discussion_id: discussion.id,
        anchor_type: discussion.anchor_type,
        anchor_id: discussion.anchor_id
      }
    )
  end

  def self.notify_outreach_pending_admin(outreach:)
    admins = outreach.company.company_users.where(role: "company_admin", status: "active")
    reviewer_name = outreach.reviewer_user.name
    notify(
      type: :outreach_pending_admin,
      company: outreach.company,
      recipients: admins,
      title: "Reviewer outreach awaiting approval",
      body: "#{reviewer_name} requested to contact a #{outreach.recipient_type.tr('_', ' ')} via #{outreach.channel}.",
      action_url: "#{app_host}/company/outreaches/#{outreach.id}",
      metadata: {
        outreach_id: outreach.id,
        reviewer_user_id: outreach.reviewer_user_id,
        purpose: outreach.purpose,
        channel: outreach.channel
      }
    )
  end

  def self.notify_outreach_received(outreach:, recipient:)
    reviewer_name = outreach.reviewer_user.name
    notify(
      type: :outreach_received,
      company: outreach.company,
      recipients: recipient,
      title: "Reviewer question for your company",
      body: "#{reviewer_name}: #{outreach.body.to_s.truncate(160)}",
      action_url: "#{app_host}/company/outreaches/#{outreach.id}",
      metadata: {
        outreach_id: outreach.id,
        reviewer_user_id: outreach.reviewer_user_id,
        purpose: outreach.purpose,
        channel: outreach.channel,
        recipient_type: outreach.recipient_type
      }
    )
  end

  def self.notify_outreach_reply(outreach:, reply:)
    notify(
      type: :outreach_reply,
      company: outreach.company,
      recipients: outreach.reviewer_user,
      title: "Reply to your outreach",
      body: reply.body.to_s.truncate(200),
      action_url: "#{app_host}/reviewer/companies/#{outreach.company_id}/outreaches/#{outreach.id}",
      metadata: {
        outreach_id: outreach.id,
        reply_id: reply.id,
        channel: reply.channel
      }
    )
  end

  def self.notify_platform_admins(type:, company:, title:, body:, action_url: nil, metadata: {})
    recipients = PlatformUser.all
    notify(
      type: type,
      company: company,
      recipients: recipients,
      title: title,
      body: body,
      action_url: action_url,
      metadata: metadata
    )
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
