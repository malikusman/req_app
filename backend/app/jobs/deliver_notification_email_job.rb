# frozen_string_literal: true

class DeliverNotificationEmailJob < ApplicationJob
  queue_as :default

  def perform(recipient_type, recipient_id)
    recipient = recipient_type.constantize.find_by(id: recipient_id)
    return unless recipient

    notification = Notification.where(
      recipient_type: recipient_type,
      recipient_id: recipient_id,
      emailed_at: nil
    ).order(created_at: :desc).first

    return unless notification

    NotificationMailer.event_email(notification, recipient).deliver_now
    notification.update!(emailed_at: Time.current)
  rescue StandardError => e
    Rails.logger.warn("[Email] delivery skipped: #{e.message}")
  end
end
