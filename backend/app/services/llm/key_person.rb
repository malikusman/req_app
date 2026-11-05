# frozen_string_literal: true

module Llm
  # The switch for the conversations with leadership (P02, P03, P04). Off only
  # when explicitly disabled; with it off, or with no model configured, the
  # conversation isn't offered and the dashboard says the team will arrange it.
  module KeyPerson
    module_function

    def enabled?
      ENV.fetch("AI_KEY_PERSON", "true").to_s.downcase != "false"
    end
  end
end
