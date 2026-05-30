# frozen_string_literal: true

class EmployeeInvitationMailer < ApplicationMailer
  default from: ENV.fetch("FROM_EMAIL", "notifications@reqapp.local")

  def invite(invitation)
    @invitation = invitation
    @employee = invitation.employee
    @company = invitation.company
    @company.ensure_join_code!
    @join_code = @company.join_code
    @whatsapp_number = @company.bot_phone_display

    mail(
      to: invitation.email,
      subject: "Join #{@company.display_name || @company.name} — workflow discovery on WhatsApp"
    )
  end
end
