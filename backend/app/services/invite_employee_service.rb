# frozen_string_literal: true

class InviteEmployeeService
  PREFERRED_CHANNELS = %w[whatsapp web both].freeze

  # Staff are invited only once the client has accepted the Stage 1 price, and
  # someone beyond what it covers only when the client confirms the extra
  # charge (Engagements::StaffInvitations). planned_participant: the onboarding
  # plan's row for this person, if they were planned.
  def self.call(company:, phone_e164:, display_name: nil, department: nil, email: nil, invited_by: nil,
                send_whatsapp: true, preferred_channel: "whatsapp", confirm_additional: false,
                planned_participant: nil)
    staff = Engagements::StaffInvitations.new(company)
    additional = staff.check!(adding: 1, confirmed: confirm_additional).positive?

    normalized_email = email.to_s.strip.downcase.presence
    channel = PREFERRED_CHANNELS.include?(preferred_channel.to_s) ? preferred_channel.to_s : "whatsapp"

    employee = company.employees.create!(
      phone_e164: PhoneNormalizer.call(phone_e164),
      display_name: display_name,
      department: department,
      email: normalized_email,
      preferred_channel: channel,
      participation_status: "invited",
      onboarding_step: display_name.present? ? "awaiting_consent" : "awaiting_name",
      invited_at: Time.current,
      verified_at: display_name.present? ? Time.current : nil,
      invited_by_company_user: invited_by
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
        discover_url: web_session[:url]
      ).deliver_later
    end

    should_send_whatsapp = send_whatsapp && channel != "web"
    SendEmployeeInvitationJob.perform_later(invitation.id) if should_send_whatsapp

    company.promote_to_hybrid_engagement!
    if additional
      staff.flag_added!(employee, planned: planned_participant)
    else
      planned_participant&.update!(employee: employee)
    end

    {
      employee: employee,
      invitation: invitation,
      discover_url: web_session&.dig(:url),
      additional: additional
    }
  end
end
