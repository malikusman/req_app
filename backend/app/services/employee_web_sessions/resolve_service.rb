# frozen_string_literal: true

module EmployeeWebSessions
  class ResolveService
    def self.call(token:)
      digest = TokenDigest.digest(token)
      EmployeeWebSession.active.includes(employee: :company).find_by(token_digest: digest)
    end
  end
end
