# frozen_string_literal: true

# Stage 1 pricing (Doc 17). The model client P24 uses: scripted replies for demos
# and tests outside production when asked for, otherwise the configured model.
module Pricing
  def self.client_for(company)
    scripted = !Rails.env.production? &&
               (ENV["PRICING_SCRIPTED_REPLIES"] == "1" ||
                company&.merged_settings&.dig("pricing_scripted_replies") == true)
    scripted ? ScriptedClient.new : Openai::Client.new
  end
end
