# frozen_string_literal: true

module Auth
  class SetPassword
    class Error < StandardError; end

    MIN_LENGTH = 8

    def self.call(token:, password:, password_confirmation:)
      new(token: token, password: password, password_confirmation: password_confirmation).call
    end

    def initialize(token:, password:, password_confirmation:)
      @token = token
      @password = password.to_s
      @password_confirmation = password_confirmation.to_s
    end

    def call
      record = PasswordResetToken.verify(@token)
      raise Error, "This link is invalid or has expired" unless record

      raise Error, "Password must be at least #{MIN_LENGTH} characters" if @password.length < MIN_LENGTH
      raise Error, "Passwords do not match" if @password != @password_confirmation

      case record
      when CompanyUser
        activate_company_user!(record)
      when ReviewerUser
        activate_reviewer!(record)
      when PlatformUser
        record.update!(password: @password)
        record.regenerate_jti!
      else
        raise Error, "Unsupported account type"
      end

      record
    end

    private

    def activate_company_user!(user)
      company = user.company
      unless company.approval_status == "approved"
        raise Error, "Your company account is not approved yet"
      end

      user.update!(
        password: @password,
        status: "active",
        invitation_accepted_at: Time.current,
        invitation_token: nil
      )
      user.regenerate_jti!
    end

    def activate_reviewer!(reviewer)
      unless reviewer.status.in?(%w[pending active])
        raise Error, "This reviewer account cannot set a password"
      end

      attrs = { password: @password }
      attrs[:status] = "active" if reviewer.status == "pending"
      attrs[:approved_at] = Time.current if reviewer.approved_at.blank? && attrs[:status] == "active"
      reviewer.update!(attrs)
      reviewer.regenerate_jti!
    end
  end
end
