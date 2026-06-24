# frozen_string_literal: true

class EmployeeInviteMailer < ApplicationMailer
  default from: ENV.fetch("FROM_EMAIL", "notifications@reqapp.local")

  def invite(employee:, company:, access_code:, discover_url:)
    @employee = employee
    @company = company
    @company_name = company.display_name || company.name
    @access_code = access_code
    @discover_url = discover_url

    mail(
      to: employee.email,
      subject: "Your #{@company_name} workflow discovery interview"
    )
  end
end
