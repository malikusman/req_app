# frozen_string_literal: true

module Llm
  # Drops LLM prose carrying a figure we cannot trace back to real evidence.
  #
  # A model told to cite only real numbers will still occasionally invent one, and a
  # fabricated statistic in a client deliverable — or in a package a consultant is
  # about to act on — is worse than saying nothing. So the guardrail is mechanical:
  # collect every significant figure that appears in the evidence, then reject any
  # sentence containing a significant figure that isn't in that set.
  #
  # Extracted from Reports::NarrativeWriter so the discovery package uses the same
  # guard rather than a second implementation of it.
  module GroundedNumbers
    # "Significant" figures we require to be grounded. Bare 1-2 digit counts
    # ("6 frictions", "3 people") are left alone to avoid false positives.
    SIGNIFICANT_NUMBER = /
      AED\s?[\d,]+(?:\.\d+)? | \$\s?[\d,]+(?:\.\d+)? |   # currency
      \d{1,3}(?:,\d{3})+(?:\.\d+)? |                      # thousands
      \d+\.\d+ |                                          # decimals
      \d+\s?% |                                           # percentages
      \d+\s?(?:[-–—]|to)\s?\d+                            # ranges (11-14, 3 to 12)
    /xi

    module_function

    # Every significant figure appearing anywhere in the given evidence strings.
    def allowed_numbers(*sources)
      sources.flatten.each_with_object(Set.new) do |source, set|
        source.to_s.scan(SIGNIFICANT_NUMBER) { |token| set << canon(token) }
      end
    end

    def canon(token)
      token.to_s.downcase.gsub(/\s+/, "").tr("–—", "--").gsub("to", "-")
    end

    # True when every significant figure in `text` traces to the evidence. Text with
    # no significant figures is trivially grounded.
    def grounded?(text, allowed)
      text.to_s.scan(SIGNIFICANT_NUMBER).all? { |token| allowed.include?(canon(token)) }
    end

    # The text if it's grounded, otherwise nil — the common call shape.
    def keep_if_grounded(text, allowed)
      value = text.to_s.strip
      return nil if value.blank?

      grounded?(value, allowed) ? value : nil
    end
  end
end
