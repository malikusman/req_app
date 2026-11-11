# frozen_string_literal: true

module Llm
  # The switch for consolidation and synthesis's model steps (P10, P11). Off
  # only when explicitly disabled. With it off, or with no model configured,
  # every candidate pair is kept separate and queued for the consultant, and
  # findings and clusters pass forward unsynthesised (P10 §8, P11 §9) — the
  # effort arithmetic and the report's figures do not depend on it.
  module Synthesis
    module_function

    def enabled?
      ENV.fetch("AI_SYNTHESIS", "true").to_s.downcase != "false"
    end
  end
end
