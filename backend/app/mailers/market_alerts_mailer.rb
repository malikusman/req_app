# frozen_string_literal: true

class MarketAlertsMailer < ApplicationMailer
  default from: ENV.fetch("FROM_EMAIL", "notifications@reqapp.local")

  def alert_email(alert)
    @alert = alert
    @employee = alert.employee
    @company = alert.company
    @candidate = alert.catalog_candidate
    @body = alert.email_body || {}

    mail(
      to: @employee.email,
      subject: "#{@body['headline'].presence || 'AI update for your role'} — #{@company.display_name || @company.name}"
    )
  end
end
