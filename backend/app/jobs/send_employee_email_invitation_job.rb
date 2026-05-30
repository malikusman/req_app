# frozen_string_literal: true

class SendEmployeeEmailInvitationJob < ApplicationJob
  queue_as :default

  def perform(employee_invitation_id)
    invitation = EmployeeInvitation.find(employee_invitation_id)
    return if invitation.email.blank?

    company = invitation.company
    company.ensure_join_code!

    EmployeeInvitationMailer.invite(invitation).deliver_now
    invitation.update!(delivery_status: "sent", sent_at: Time.current, invite_channel: "email")
  rescue StandardError => e
    invitation&.update!(delivery_status: "failed", error_message: e.message, sent_at: Time.current)
  end
end
