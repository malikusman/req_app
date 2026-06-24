# frozen_string_literal: true

module EmployeeWebSessions
  module TokenDigest
    module_function

    def digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end
  end
end
