# frozen_string_literal: true

class OutreachMailer < ApplicationMailer
  default from: ENV.fetch("FROM_EMAIL", "notifications@reqapp.local")

  def request_email(outreach, token)
    @outreach = outreach
    @token = token
    @company = outreach.company
    @reply_url = "#{NotificationService.app_host}/outreach/reply/#{token}"
    @body = outreach.delivery_body

    mail(
      to: recipient_email(outreach),
      subject: "Clarification request from consultant — #{@company.display_name || @company.name}"
    )
  end

  private

  def recipient_email(outreach)
    if outreach.recipient_type == "employee"
      outreach.employee&.email
    else
      admin = outreach.company.company_users.find_by(id: outreach.recipient_id) ||
              outreach.company.company_users.where(role: "company_admin", status: "active").first
      admin&.email
    end
  end
end
