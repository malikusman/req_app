# frozen_string_literal: true

module Pricing
  # An amount as a client reads it: "AED 42,000", or "AED 2,287.50" when there
  # are cents.
  module Money
    def self.format(amount, currency)
      value = BigDecimal(amount.to_s)
      whole = value.frac.zero?
      figure = ActiveSupport::NumberHelper.number_to_delimited(whole ? value.to_i : format_cents(value))
      "#{currency} #{figure}"
    end

    def self.format_cents(value) = Kernel.format("%.2f", value)
  end
end
