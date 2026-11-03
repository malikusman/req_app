# frozen_string_literal: true

module Llm
  # The switch for the onboarding pre-fill's model step (P01). Off only when
  # explicitly disabled; with it off, or with no model configured, onboarding
  # shows the plain form.
  module Prefill
    module_function

    def enabled?
      ENV.fetch("AI_PREFILL", "true").to_s.downcase != "false"
    end
  end
end
