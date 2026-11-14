# frozen_string_literal: true

module Llm
  # The switch for P24, the Stage 1 price explainer. Off only when explicitly
  # disabled; with it off, or with no model configured, the administrator sees
  # the computed derivation without a narrative and the client reads the
  # template scope statement (P24 §7).
  module Pricing
    module_function

    def enabled?
      ENV.fetch("AI_PRICING_EXPLAINER", "true").to_s.downcase != "false"
    end
  end
end
