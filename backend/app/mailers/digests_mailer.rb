# frozen_string_literal: true

class DigestsMailer < ApplicationMailer
  default from: ENV.fetch("FROM_EMAIL", "notifications@reqapp.local")

  def digest_email(digest)
    @digest = digest
    @employee = digest.employee
    @company = digest.company
    @content = digest.content || {}

    mail(
      to: @employee.email,
      subject: "#{@content['headline'].presence || 'Your workflow insights'} — #{@company.display_name || @company.name}"
    )
  end
end
