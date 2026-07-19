# frozen_string_literal: true

class DemoRequestMailer < ApplicationMailer
  def notify(demo_request)
    @demo_request = demo_request
    mail(
      to: ENV.fetch("SALES_INBOX", "sales@worktruth.com"),
      subject: "Demo request — #{demo_request.company_name} (#{demo_request.name})"
    )
  end
end
