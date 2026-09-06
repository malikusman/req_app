# frozen_string_literal: true

module Auth
  class RequestPasswordReset
    class Error < StandardError; end

    PORTALS = {
      "company" => CompanyUser,
      "consultant" => ConsultantUser,
      "platform" => PlatformUser,
      # Password-reset and set-password emails sent before the rename carry
      # portal=reviewer in their link, and those links must keep working.
      "reviewer" => ConsultantUser
    }.freeze

    def self.call(portal:, email:)
      new(portal: portal, email: email).call
    end

    def initialize(portal:, email:)
      @portal = portal.to_s
      @email = email.to_s.strip.downcase
    end

    def call
      klass = PORTALS[@portal]
      raise Error, "Unknown portal" unless klass
      raise Error, "Email is required" if @email.blank?

      user = find_resettable(klass)
      # Always succeed to avoid account enumeration.
      return true unless user

      token = PasswordResetToken.generate(user)
      SignupMailer.password_reset(user, token, @portal).deliver_later
      true
    end

    private

    def find_resettable(klass)
      case klass.name
      when "CompanyUser"
        user = CompanyUser.find_by(email: @email)
        return nil unless user
        return nil unless user.status.in?(%w[pending active])
        return nil unless user.company.approval_status == "approved"

        user
      when "ConsultantUser"
        ConsultantUser.find_by(email: @email, status: %w[pending active])
      when "PlatformUser"
        PlatformUser.find_by(email: @email)
      end
    end
  end
end
