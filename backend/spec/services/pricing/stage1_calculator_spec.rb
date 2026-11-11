# frozen_string_literal: true

require "rails_helper"

# The Stage 1 fee is worked out in code, the same way every time (Doc 17 §2.3,
# §16), against fully loaded cost and the margin floor (§8). Figures here use
# rate card version 1's placeholder values (Pricing::Defaults).
RSpec.describe Pricing::Stage1Calculator do
  before { Pricing::Defaults.ensure! }

  let(:rate_card) { RateCardVersion.find_by!(version: 1) }
  let(:floor) { MarginFloorVersion.find_by!(version: 1) }
  let(:departments) do
    [{ "name" => "Sales", "count" => 5 }, { "name" => "Procurement", "count" => 4 }, { "name" => "Finance", "count" => 3 }]
  end

  def inputs(**overrides)
    Pricing::Stage1Inputs.new(**{ participants: 12, departments: departments, key_persons: 1, named_participants: 12,
                                  languages: %w[en ar], locations: 1, country: "AE", deep_dives: nil }.merge(overrides))
  end

  def estimate(given = inputs, card: rate_card, floor_version: floor, comparables: [])
    described_class.call(inputs: given, rate_card: card, floor: floor_version, comparables: comparables)
  end

  def amounts(result) = result.lines.to_h { |l| [l["key"], l["amount"]] }

  # Doc 17 §19: twelve participants, three departments, two languages.
  it "builds the fee from its components, with hours and margin" do
    result = estimate

    expect(amounts(result)).to eq("base" => 18_000, "participants" => 18_000, "deep_dives" => 8_750,
                                  "complexity" => 1_000)
    expect(result.deep_dives).to eq(5)
    expect(result.subtotal).to eq(BigDecimal("45750"))
    expect(result.tax_amount).to eq(BigDecimal("2287.50"))
    expect(result.total).to eq(BigDecimal("48037.50"))
    expect(result.additional_participant_rate).to eq(BigDecimal("1500"))
    expect(result.total_hours).to eq(BigDecimal("31.5"))
    expect(result.cost).to include("consultant_time" => BigDecimal("7875"), "ai_usage" => BigDecimal("820"),
                                   "total" => BigDecimal("10695"))
    expect(result.margin_percent).to eq(BigDecimal("76.62"))
    expect(result.below_floor?).to be(false)
  end

  it "defaults the deep dives to the participant count, kept within three to five (D9)" do
    expect([1, 4, 9].map { |n| estimate(inputs(participants: n)).deep_dives }).to eq([3, 4, 5])
    expect(estimate(inputs(deep_dives: 2)).deep_dives).to eq(2)
  end

  it "adds no complexity line for one language, one location and few departments" do
    result = estimate(inputs(languages: %w[en]))
    expect(result.lines.map { |l| l["key"] }).not_to include("complexity")
  end

  it "charges complexity for each extra language, location and department over the threshold" do
    result = estimate(inputs(languages: %w[en ar], locations: 3,
                             departments: departments + [{ "name" => "HR", "count" => 1 }, { "name" => "IT", "count" => 1 }]))

    line = result.lines.find { |l| l["key"] == "complexity" }
    expect(line["amount"]).to eq(BigDecimal("3500")) # 1,000 + 2 × 750 + 2 × 500
    expect(line["detail"]).to eq("2 working languages, 3 locations, 5 departments")
  end

  it "rounds each line to a whole unit and tax half up to the cent" do
    stage1 = Pricing::Defaults::STAGE1_V1.deep_dup
    stage1["base_fee"] = 18_332.5
    stage1["tax_rates"] = { "AE" => 0.0525 }
    card = create(:rate_card_version, stage1: stage1)

    result = estimate(inputs(participants: 3, languages: %w[en], departments: [{ "name" => "Sales", "count" => 3 }]),
                      card: card)

    expect(amounts(result)["base"]).to eq(BigDecimal("18333"))
    expect(result.subtotal).to eq(BigDecimal("28083")) # 18,333 + 4,500 + 5,250
    expect(result.tax_amount).to eq(BigDecimal("1474.36")) # 1,474.3575
  end

  it "won't estimate while a count is missing" do
    expect { estimate(inputs(participants: nil)) }.to raise_error(described_class::NotEstimable)
  end

  it "won't estimate from a rate card missing a rate" do
    expect { estimate(inputs(country: "SA")) }.to raise_error(described_class::MissingRate, /tax rate for SA/)

    stage1 = Pricing::Defaults::STAGE1_V1.deep_dup.tap { |s| s.delete("licences") }
    card = build(:rate_card_version, stage1: stage1)
    expect { estimate(card: card) }.to raise_error(described_class::MissingRate, /licences/)
  end

  it "flags a margin below the floor, and only below it" do
    at_margin = create(:margin_floor_version, value: BigDecimal("0.7662"))
    just_above = create(:margin_floor_version, value: BigDecimal("0.7663"))

    expect(estimate(floor_version: at_margin).below_floor?).to be(false)
    expect(estimate(floor_version: just_above).below_floor?).to be(true)
  end

  it "keeps the calculated lines and adds the difference when the price is adjusted" do
    adjusted = estimate.adjusted(30_000)

    expect(adjusted.lines.last).to include("key" => "adjustment", "amount" => BigDecimal("-15750"))
    expect(adjusted.subtotal).to eq(BigDecimal("30000"))
    expect(adjusted.cost["total"]).to eq(BigDecimal("10695"))
    expect(adjusted.margin_percent).to eq(BigDecimal("64.35"))
    expect(adjusted.adjusted(45_750).lines.map { |l| l["key"] }).not_to include("adjustment")
  end

  it "gives the same result for the same inputs" do
    expect(estimate.to_h).to eq(estimate.to_h)
  end

  it "survives being stored and read back" do
    stored = JSON.parse(estimate.to_h.to_json)
    expect(Pricing::Stage1Estimate.from_h(stored, floor: floor).to_h).to eq(estimate.to_h)
  end

  it "names what could make the estimate wrong, and lowers confidence for it" do
    result = estimate(inputs(named_participants: 9, departments: departments + [{ "name" => "HR", "count" => 1 }]))

    expect(result.risk_signals.map { |s| s["code"] })
      .to contain_exactly("NO_COMPARABLES", "SEVERAL_LANGUAGES", "PARTICIPANTS_NOT_NAMED", "THIN_DEPARTMENT",
                          "PLACEHOLDER_RATES")
    expect(result.confidence).to eq("LOW")

    calm = estimate(inputs(languages: %w[en]), comparables: [{ "participants" => 12 }])
    expect(calm.confidence).to eq("HIGH")
  end
end
