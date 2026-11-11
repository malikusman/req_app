# frozen_string_literal: true

FactoryBot.define do
  factory :rate_card_version do
    version { RateCardVersion.next_version }
    effective_from { 1.day.ago }
    currency { "AED" }
    rates { Pricing::Defaults::RATES_V1 }
    stage1 { Pricing::Defaults::STAGE1_V1 }
    reason { "Test rates" }
  end

  factory :margin_floor_version do
    version { MarginFloorVersion.next_version }
    effective_from { 1.day.ago }
    value { BigDecimal("0.60") }
    reason { "Test floor" }
  end

  # A Stage 1 quote with simple figures; the calculator's own specs check the
  # arithmetic.
  factory :quote do
    engagement
    company { engagement.company }
    quote_stage { "STAGE_1" }
    version { Quote.next_version_for(engagement, quote_stage) }
    status { "PROPOSED" }
    currency { "AED" }
    rate_card_version { Pricing::Defaults.ensure! && RateCardVersion.current }
    margin_floor_version { MarginFloorVersion.current }
    line_items { [{ "key" => "base", "label" => "Base engagement", "quantity" => 1, "amount" => "18000.0" }] }
    subtotal { BigDecimal("18000") }
    tax_rate { BigDecimal("0.05") }
    tax_amount { BigDecimal("900") }
    total { BigDecimal("18900") }
    additional_participant_rate { BigDecimal("1500") }
    participants_included { 5 }
    deep_dives_included { 3 }
    internal { { "cost" => "5000.0", "hours" => "20.0" } }
    margin_percent { BigDecimal("72.22") }
    below_floor { false }

    trait :issued do
      status { "ISSUED" }
      approved_by factory: :platform_user
      approved_at { Time.current }
      issued_at { Time.current }
      valid_until { 30.days.from_now.to_date }
    end
  end
end
