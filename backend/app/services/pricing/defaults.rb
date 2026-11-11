# frozen_string_literal: true

module Pricing
  # The first rate card and margin floor, so Stage 1 can be priced before the
  # real values are agreed. The fee and rate values are placeholders — they are
  # an open commercial decision (Decision Register K2) — and the rate card says
  # so, which the administrator's screens show. The floor is decided (B12).
  #
  # These are version 1 as it was seeded. Never change them here: a new value is
  # a new version, made by an administrator with a reason (Doc 17 §8.3).
  module Defaults
    RATES_V1 = {
      "consultant" => { "mjadi_team" => { "internal_cost" => 250, "charge_rate" => 750 } }
    }.freeze

    STAGE1_V1 = {
      "base_fee" => 18_000,
      "per_participant_fee" => 1_500,
      "per_deep_dive_fee" => 1_750,
      "complexity" => {
        "per_extra_language" => 1_000,
        "per_extra_location" => 750,
        "departments_threshold" => 3,
        "per_department_over_threshold" => 500
      },
      "additional_participant_rate" => 1_500,
      "hours" => {
        "base" => 12,
        "per_participant" => 0.75,
        "per_deep_dive" => 1.5,
        "per_key_person" => 1,
        "per_extra_language" => 2,
        "per_extra_location" => 1
      },
      "ai_cost" => { "per_participant" => 40, "per_deep_dive" => 60, "per_key_person" => 40 },
      "platform_allocation" => 1_500,
      "licences" => 500,
      "deep_dives" => { "min" => 3, "max" => 5 },
      "tax_rates" => { "AE" => 0.05 },
      "validity_days" => 30,
      "payment_terms_text" => "Payment terms are set out in your engagement terms.",
      "terms_reference_text" => "This proposal is governed by Mjadi's engagement terms, including what happens " \
                                "if an item you later choose for design proves not viable."
    }.freeze

    FLOOR_V1 = BigDecimal("0.60")

    def self.ensure!
      RateCardVersion.first || RateCardVersion.create!(
        version: 1, effective_from: Time.zone.parse("2026-11-01"), currency: "AED", rates: RATES_V1, stage1: STAGE1_V1,
        placeholder: true, reason: "Placeholder values until the rate card and Stage 1 formula are agreed (Decision Register K2)"
      )
      MarginFloorVersion.first || MarginFloorVersion.create!(
        version: 1, value: FLOOR_V1, effective_from: Time.zone.parse("2026-11-01"),
        reason: "Minimum gross margin on fully loaded cost (Decision Register B12)"
      )
    end
  end
end
