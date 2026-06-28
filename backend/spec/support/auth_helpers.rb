# frozen_string_literal: true

module AuthHelpers
  def auth_headers_for(user)
    payload = case user
              when CompanyUser
                {
                  sub: "company_user:#{user.id}",
                  aud: "company",
                  company_id: user.company_id,
                  role: user.role,
                  jti: user.jti
                }
              when PlatformUser
                {
                  sub: "platform_user:#{user.id}",
                  aud: "platform",
                  role: user.role,
                  jti: user.jti
                }
              when ReviewerUser
                {
                  sub: "reviewer_user:#{user.id}",
                  aud: "reviewer",
                  jti: user.jti
                }
              else
                raise ArgumentError, "Unsupported user type: #{user.class}"
              end
    token = JsonWebToken.encode(payload)
    { "Authorization" => "Bearer #{token}" }
  end

  def internal_headers
    { "X-Internal-Token" => ENV.fetch("INTERNAL_API_TOKEN", "test-internal-token") }
  end

  def employee_web_headers(session:, employee:)
    token = JsonWebToken.encode(
      {
        sub: "employee:#{employee.id}",
        aud: "employee_web",
        employee_id: employee.id,
        web_session_id: session.id,
        company_id: employee.company_id,
        jti: SecureRandom.uuid
      },
      expires_at: session.expires_at
    )
    { "Authorization" => "Bearer #{token}" }
  end
end
