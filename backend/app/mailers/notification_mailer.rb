# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  default from: ENV.fetch("FROM_EMAIL", "notifications@reqapp.local")

  def event_email(notification, recipient)
    @notification = notification
    @recipient = recipient
    mail(
      to: recipient.email,
      subject: notification.title
    )
  end
end
