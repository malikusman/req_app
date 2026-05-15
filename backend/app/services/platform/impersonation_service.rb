# frozen_string_literal: true

module Platform
  class ImpersonationService
    SESSION_TTL = 2.hours

    def self.start!(platform_user:, company:, request: nil)
      new(platform_user: platform_user, company: company, request: request).start!
    end

    def initialize(platform_user:, company:, request: nil)
      @platform_user = platform_user
      @company = company
      @request = request
    end

    def start!
      company_user = @company.company_users.find_by(role: "company_admin", status: "active") ||
                     @company.company_users.find_by(status: "active")
      raise ActiveRecord::RecordNotFound, "No active company user" unless company_user

      jti = SecureRandom.uuid
      session = ImpersonationSession.create!(
        platform_user: @platform_user,
        company_user: company_user,
        company: @company,
        token_jti: jti,
        expires_at: SESSION_TTL.from_now,
        ip_address: @request&.remote_ip
      )

      token = JsonWebToken.encode(
        {
          sub: "company_user:#{company_user.id}",
          aud: "company",
          company_id: @company.id,
          role: company_user.role,
          jti: jti,
          impersonation: true,
          platform_user_id: @platform_user.id,
          impersonation_session_id: session.id
        },
        expires_at: session.expires_at
      )

      PlatformAuditService.log!(
        platform_user: @platform_user,
        action: "impersonation_started",
        target: @company,
        metadata: {
          company_user_id: company_user.id,
          impersonation_session_id: session.id
        },
        request: @request
      )

      {
        token: token,
        expires_at: session.expires_at,
        company_user: company_user,
        company: @company
      }
    end
  end
end
