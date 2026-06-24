# frozen_string_literal: true

class InviteEmployeeService
  PREFERRED_CHANNELS = %w[whatsapp web both].freeze

  def self.call(company:, phone_e164:, display_name: nil, department: nil, email: nil, invited_by: nil,
                send_whatsapp: true, preferred_channel: "whatsapp")
    normalized_email = email.to_s.strip.downcase.presence
    channel = PREFERRED_CHANNELS.include?(preferred_channel.to_s) ? preferred_channel.to_s : "whatsapp"

    employee = company.employees.create!(
      phone_e164: PhoneNormalizer.call(phone_e164),
      display_name: display_name,
      department: department,
      email: normalized_email,
      preferred_channel: channel,
      participation_status: "invited",
      onboarding_step: display_name.present? ? "awaiting_access_code" : "awaiting_name",
      invited_at: Time.current,
      invited_by_company_user: invited_by
    )

    _code_record, plain_code = EmployeeAccessCode.issue_for!(
      employee: employee,
      issued_by_type: invited_by ? "company_user" : "system"
    )

    invitation = EmployeeInvitation.create!(
      company: company,
      employee: employee,
      company_user: invited_by,
      phone_e164: employee.phone_e164,
      batch_id: SecureRandom.uuid,
      delivery_status: "queued"
    )

    web_session = nil
    if channel.in?(%w[web both]) && normalized_email.present?
      web_session = EmployeeWebSessions::IssueService.call(employee: employee)
      EmployeeInviteMailer.invite(
        employee: employee,
        company: company,
        access_code: plain_code,
        discover_url: web_session[:url]
      ).deliver_later
    end

    should_send_whatsapp = send_whatsapp && channel != "web"
    SendEmployeeInvitationJob.perform_later(invitation.id) if should_send_whatsapp

    company.increment!(:invited_count)

    {
      employee: employee,
      access_code: plain_code,
      invitation: invitation,
      discover_url: web_session&.dig(:url)
    }
  end
end
