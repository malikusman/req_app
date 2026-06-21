# frozen_string_literal: true

class InviteEmployeeService
  def self.call(company:, phone_e164:, display_name: nil, department: nil, invited_by: nil, send_whatsapp: true)
    employee = company.employees.create!(
      phone_e164: PhoneNormalizer.call(phone_e164),
      display_name: display_name,
      department: department,
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

    SendEmployeeInvitationJob.perform_later(invitation.id) if send_whatsapp

    company.increment!(:invited_count)

    { employee: employee, access_code: plain_code, invitation: invitation }
  end
end
