# frozen_string_literal: true

module EmployeeWebSessions
  class IssueService
    DEFAULT_TTL = 14.days

    def self.call(employee:, expires_at: nil)
      new(employee: employee, expires_at: expires_at).call
    end

    def initialize(employee:, expires_at: nil)
      @employee = employee
      @company = employee.company
      @expires_at = expires_at || DEFAULT_TTL.from_now
    end

    def call
      token = SecureRandom.urlsafe_base64(32)
      session = EmployeeWebSession.create!(
        employee: @employee,
        company: @company,
        token_digest: TokenDigest.digest(token),
        expires_at: @expires_at
      )

      {
        session: session,
        token: token,
        url: discover_url(token),
        expires_at: @expires_at
      }
    end

    private

    def discover_url(token)
      host = ENV.fetch("APP_HOST", "http://localhost:5173")
      "#{host.chomp('/')}/discover/#{token}"
    end
  end
end
