# frozen_string_literal: true

class InviteEmployeeService
  def self.call(company:, phone_e164: nil, email: nil, display_name: nil, department: nil, invited_by: nil, send_whatsapp: true, send_email: true)
    normalized_phone = phone_e164.present? ? PhoneNormalizer.call(phone_e164) : nil
    normalized_email = email.to_s.strip.downcase.presence
    raise ArgumentError, "phone_e164 or email is required" unless normalized_phone.present? || normalized_email.present?

    company.ensure_join_code!

    employee = company.employees.create!(
      phone_e164: normalized_phone,
      email: normalized_email,
      display_name: display_name,
      department: department,
      participation_status: "invited",
      onboarding_step: "awaiting_name",
      invited_at: Time.current,
      invited_by_company_user: invited_by
    )

    invitation = EmployeeInvitation.create!(
      company: company,
      employee: employee,
      company_user: invited_by,
      phone_e164: employee.phone_e164,
      email: employee.email,
      invite_channel: employee.phone_e164.present? ? "whatsapp" : "email",
      batch_id: SecureRandom.uuid,
      delivery_status: "queued"
    )

    SendEmployeeInvitationJob.perform_later(invitation.id) if send_whatsapp && employee.phone_e164.present?
    SendEmployeeEmailInvitationJob.perform_later(invitation.id) if send_email && employee.email.present?

    company.increment!(:invited_count)

    { employee: employee, company_join_code: company.join_code, invitation: invitation }
  end
end
