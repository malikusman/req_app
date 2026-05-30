# frozen_string_literal: true

class SendEmployeeInvitationJob < ApplicationJob
  queue_as :default

  def perform(employee_invitation_id)
    invitation = EmployeeInvitation.find(employee_invitation_id)
    employee = invitation.employee
    company = invitation.company
    client = Whatsapp::MetaClient.new

    unless client.configured?
      invitation.update!(
        delivery_status: "failed",
        error_message: "WhatsApp API not configured",
        sent_at: Time.current
      )
      return
    end

    response = client.send_invitation_template(
      to: employee.phone_e164,
      employee_name: employee.display_name,
      company_name: company.display_name || company.name
    )

    meta_id = response.dig("messages", 0, "id")
    invitation.update!(
      delivery_status: "sent",
      meta_message_id: meta_id,
      sent_at: Time.current,
      invite_channel: "whatsapp",
      whatsapp_template_name: ENV.fetch("META_TEMPLATE_EMPLOYEE_INVITE", "employee_discovery_invite")
    )
    WhatsappDeliveryMetric.record!("template_sent", metadata: { invitation_id: invitation.id })
  rescue Whatsapp::MetaClient::ApiError => e
    invitation.update!(delivery_status: "failed", error_message: e.message, sent_at: Time.current)
    WhatsappDeliveryMetric.record!("template_failed", metadata: { invitation_id: invitation.id, error: e.message })
  end
end
