# frozen_string_literal: true

module Platform
  class SetCompanyAdminPassword
    class Error < StandardError; end

    MIN_PASSWORD_LENGTH = 8

    def self.call(company:, password:)
      new(company: company, password: password).call
    end

    def initialize(company:, password:)
      @company = company
      @password = password.to_s
    end

    def call
      raise Error, "Password must be at least #{MIN_PASSWORD_LENGTH} characters" if @password.length < MIN_PASSWORD_LENGTH

      admin = @company.company_users
                      .where(role: "company_admin", status: %w[pending active])
                      .order(:id)
                      .first
      raise Error, "No company admin account on this company" unless admin

      admin.update!(password: @password, status: "active")
      admin.regenerate_jti!
      SignupMailer.company_admin_credentials(admin, @password).deliver_later
      admin
    end
  end
end
