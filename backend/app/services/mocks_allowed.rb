# frozen_string_literal: true

# Controls whether silent mock / fallback behaviour is allowed when external
# services (OpenAI, Stripe, Gotenberg) are not configured.
#
# Production/staging: mocks OFF unless ALLOW_MOCKS=1
# Development/test: mocks ON unless ALLOW_MOCKS=0
module MocksAllowed
  module_function

  def allowed?
    explicit = ENV["ALLOW_MOCKS"].to_s.strip
    return explicit == "1" if explicit.present?

    Rails.env.development? || Rails.env.test?
  end

  def require!(service_name)
    return if allowed?

    raise "#{service_name} is not configured. Set the required credentials, or ALLOW_MOCKS=1 for local demos only."
  end
end
