# frozen_string_literal: true

# Emails a consultant's follow-up question to an employee, with a link that lets
# them answer in a browser.
#
# The reply link is the point. WhatsApp only accepts free text inside a 24h window,
# and outside it an employee has to tap a template first — so an employee who never
# taps, or who does not use WhatsApp at all, previously had no way to answer a
# consultant. This gives them one.
class ConsultantFollowupMailer < ApplicationMailer
  default from: ENV.fetch("FROM_EMAIL", "notifications@reqapp.local")

  def question_email(request, raw_token)
    @request = request
    @company = request.company
    @employee = request.employee
    @body = request.body
    # Same public route the clarification links use — one endpoint resolves either
    # kind of ask, so there is one reply page rather than two.
    @reply_url = "#{NotificationService.app_host}/outreach/reply/#{raw_token}"

    mail(
      to: @employee.email,
      subject: "A quick question about your work — #{@company.display_name || @company.name}"
    )
  end
end
