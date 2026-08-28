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
  # Two kinds of figure are checked, for different reasons:
  #
  #   SIGNIFICANT_NUMBER  currency, thousands, decimals, percentages, ranges. Bare
  #                       integers are excluded on purpose, so "6 issues" or "3
  #                       people" never trips the guard.
  #
  #   QUANTITY_WITH_UNIT  a bare number WITH a unit — "14 hours a week", "3 days to
  #                       approve", "200 invoices". This is the shape that actually
  #                       gets invented in this domain, and the pattern above misses
  #                       it entirely. The unit is part of the key, so evidence
  #                       saying "2 hours" does not license a claim of "2 days".
  module GroundedNumbers
    SIGNIFICANT_NUMBER = /
      AED\s?[\d,]+(?:\.\d+)? | \$\s?[\d,]+(?:\.\d+)? |   # currency
      \d{1,3}(?:,\d{3})+(?:\.\d+)? |                      # thousands
      \d+\.\d+ |                                          # decimals
      \d+\s?% |                                           # percentages
      \d+\s?(?:[-–—]|to)\s?\d+                            # ranges (11-14, 3 to 12)
    /xi

    QUANTITY_UNITS = "hours?|hrs?|minutes?|mins?|days?|weeks?|months?|years?|" \
                     "invoices?|orders?|tickets?|emails?|documents?|files?|" \
                     "people|persons?|staff|employees?|times?|steps?"

    QUANTITY_WITH_UNIT = /\b(\d+(?:[.,]\d+)?)\s*(#{QUANTITY_UNITS})\b/i

    # "11–14 days" must license BOTH bounds with the unit. Without this, evidence
    # stating a real range would reject prose quoting either end of it — a false
    # positive that silently deletes correct sentences.
    RANGE_WITH_UNIT = /\b(\d+(?:[.,]\d+)?)\s*(?:[-–—]|to)\s*(\d+(?:[.,]\d+)?)\s*(#{QUANTITY_UNITS})\b/i

    module_function

    # Every significant figure appearing anywhere in the given evidence strings.
    def allowed_numbers(*sources)
      sources.flatten.each_with_object(Set.new) do |source, set|
        set.merge(figures(source))
      end
    end

    # The figures a piece of text asserts, canonicalised for comparison.
    def figures(text)
      value = text.to_s
      found = Set.new

      value.scan(SIGNIFICANT_NUMBER) { |token| found << canon(token) }

      value.scan(RANGE_WITH_UNIT) do |low, high, unit|
        found << quantity(low, unit)
        found << quantity(high, unit)
      end

      value.scan(QUANTITY_WITH_UNIT) { |number, unit| found << quantity(number, unit) }

      found
    end

    def canon(token)
      token.to_s.downcase.gsub(/\s+/, "").tr("–—", "--").gsub("to", "-")
    end

    # Unit is part of the key, singularised so "1 day" and "3 days" compare.
    def quantity(number, unit)
      "#{number.to_s.tr(',', '')}#{unit.to_s.downcase.sub(/s\z/, '')}"
    end

    # True when every figure in `text` traces to the evidence. Text with no figures
    # is trivially grounded.
    def grounded?(text, allowed)
      figures(text).subset?(allowed.to_set)
    end

    # The text if it's grounded, otherwise nil — the common call shape.
    def keep_if_grounded(text, allowed)
      value = text.to_s.strip
      return nil if value.blank?

      grounded?(value, allowed) ? value : nil
    end
  end
end
