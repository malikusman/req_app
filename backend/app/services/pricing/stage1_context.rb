# frozen_string_literal: true

module Pricing
  # What P24 sees (P24 §3; Doc 05 §4.3 "Pricing"): the scope of the engagement,
  # the participant plan, the computed fee and its components, the hours and
  # margin behind it, comparables, the versions applied and the risk signals —
  # nothing else.
  #
  # Built from the quote alone. Never a transcript, a management finding or
  # context, a consultant's note, an onboarding answer or anything said in a
  # conversation; comparables carry sizes and fees, never another client's
  # name (Doc 05 §4.2, Doc 17 §15). Amounts are given formatted, so the model
  # can quote them exactly and never has to work one out.
  class Stage1Context
    BLOCKS = %w[engagement participants deep_dives_expected fee_components additional_participant_rate
                expected_consultant_hours comparables margin versions risk_signals].freeze

    def self.build(quote) = new(quote).build

    def initialize(quote)
      @quote = quote
      @inputs = quote.inputs
      @estimate = quote.estimate
    end

    def build
      [
        block("engagement", "platform", engagement),
        block("participants", "platform", participants),
        block("deep_dives_expected", "platform", @quote.deep_dives_included),
        block("fee_components", "platform", fee_components),
        block("additional_participant_rate", "platform", money(@quote.additional_participant_rate)),
        block("expected_consultant_hours", "platform", hours),
        block("comparables", "platform", comparables),
        block("margin", "INTERNAL_COMMERCIAL", margin),
        block("versions", "platform", rate_card_version: @quote.rate_card_version.version,
                                      floor_version: @quote.margin_floor_version.version),
        block("risk_signals", "platform", Array(@estimate["risk_signals"]).map { |s| s["text"] }),
        "Write the administrator's explanation and the client's scope statement now."
      ].join("\n\n")
    end

    # Every amount the model may quote, as it is given.
    def self.allowed_amounts(quote)
      figures = Array(quote.line_items).map { |l| l["amount"] } +
                [quote.subtotal, quote.tax_amount, quote.total, quote.additional_participant_rate]
      figures += Array(quote.line_items).map { |l| l["unit_amount"] }
      figures += Comparables.for(quote.engagement, quote.participants_included).map { |c| c["fee"] }
      figures.map { |f| BigDecimal(f.to_s) }.uniq
    end

    private

    def engagement
      { company_industry: @inputs["industry"], company_size_band: @inputs["size_band"],
        departments_in_scope: departments.map { |d| d["name"] }, languages: @inputs["languages"],
        locations: @inputs["locations"], currency: @quote.currency }
    end

    def participants
      { total: @quote.participants_included, by_department: departments.to_h { |d| [d["name"], d["count"]] },
        key_persons_to_interview: @inputs["key_persons"], named_so_far: @inputs["named_participants"] }
    end

    def fee_components
      lines = Array(@quote.line_items).map do |l|
        { component: l["label"], quantity: l["quantity"], amount: money(l["amount"]), covers: l["detail"] }
      end
      { lines: lines, subtotal: money(@quote.subtotal),
        tax: "#{money(@quote.tax_amount)} (VAT #{(@quote.tax_rate * 100).round(2).to_s('F').sub(/\.0\z/, '')}%)",
        total: money(@quote.total) }
    end

    def hours
      { total: @estimate["total_hours"], by_activity: @estimate["hours"] }
    end

    def comparables
      Comparables.for(@quote.engagement, @quote.participants_included).map do |c|
        { participants: c["participants"], deep_dives: c["deep_dives"], fee: money(c["fee"], c["currency"]),
          estimated_hours: c["estimated_hours"], actual_hours: c["actual_hours"] || "not recorded yet" }
      end
    end

    def margin
      { margin_percent: @quote.margin_percent.to_s("F"), floor_percent: @quote.margin_floor_version.percent.to_s("F"),
        below_floor: @quote.below_floor }
    end

    def departments = Array(@inputs["departments"])

    def money(amount, currency = @quote.currency) = Money.format(amount, currency)

    def block(name, trust, value)
      "<#{name} trust=\"#{trust}\">\n#{JSON.pretty_generate(value)}\n</#{name}>"
    end
  end
end
