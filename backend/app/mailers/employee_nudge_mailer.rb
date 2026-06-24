# frozen_string_literal: true

class EmployeeNudgeMailer < ApplicationMailer
  default from: ENV.fetch("FROM_EMAIL", "notifications@reqapp.local")

  def nudge_email(employee:, company:)
    @employee = employee
    @company = company
    @company_name = company.display_name || company.name

    mail(
      to: employee.email,
      subject: "Reminder: continue your #{@company_name} discovery interview"
    )
  end
end
