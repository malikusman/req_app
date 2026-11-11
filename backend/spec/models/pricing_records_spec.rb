# frozen_string_literal: true

require "rails_helper"

# The records Stage 1 pricing keeps (Doc 06 §10, Doc 17 §8.3, §9.3): rate cards
# and floors are versioned and never edited, a quote's figures never change,
# and an override can't be saved without its structured reason.
RSpec.describe "Pricing records" do
  before { Pricing::Defaults.ensure! }

  describe RateCardVersion do
    it "is seeded with placeholder Stage 1 values until they are agreed (K2)" do
      expect(described_class.find_by(version: 1)).to have_attributes(placeholder: true, currency: "AED")
    end

    it "can't be edited once saved" do
      expect { described_class.current.update!(reason: "changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "needs every value Stage 1 reads" do
      stage1 = Pricing::Defaults::STAGE1_V1.deep_dup.tap { |s| s["hours"].delete("per_deep_dive") }
      record = build(:rate_card_version, stage1: stage1)

      expect(record).not_to be_valid
      expect(record.errors[:stage1].join).to include("hours.per_deep_dive")
    end

    it "takes the newest version in effect" do
      newer = create(:rate_card_version, reason: "Agreed values")
      create(:rate_card_version, effective_from: 1.week.from_now, reason: "Next month")

      expect(described_class.current).to eq(newer)
    end
  end

  describe MarginFloorVersion do
    it "starts at 60% (B12) and can't be edited" do
      floor = described_class.find_by(version: 1)
      expect(floor.value).to eq(BigDecimal("0.60"))
      expect { floor.update!(value: 0.5) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "needs a reason for a change" do
      expect(build(:margin_floor_version, reason: nil)).not_to be_valid
    end
  end

  describe Quote do
    let(:quote) { create(:quote) }

    it "keeps its figures as made" do
      expect(quote.update(total: 1)).to be(false)
      expect(quote.errors[:base].join).to include("total")
      expect(quote.reload.total).to eq(BigDecimal("18900"))
    end

    it "sets its validity once, when issued" do
      quote.update!(valid_until: 30.days.from_now.to_date, status: "ISSUED", approved_by: create(:platform_user),
                    approved_at: Time.current)
      expect(quote.update(valid_until: 60.days.from_now.to_date)).to be(false)
    end

    it "can't reach the client without an administrator's approval" do
      expect(quote.update(status: "ISSUED", valid_until: 30.days.from_now.to_date)).to be(false)
      expect(quote.errors[:base].join).to include("administrator must approve")
    end

    it "records who accepted it" do
      issued = create(:quote, :issued)
      expect(issued.update(status: "ACCEPTED")).to be(false)
    end

    it "allows one open quote per engagement and stage" do
      expect { create(:quote, engagement: quote.engagement) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "numbers versions per engagement" do
      quote.update!(status: "SUPERSEDED")
      expect(create(:quote, engagement: quote.engagement, parent_quote: quote).version).to eq(2)
    end
  end

  describe EstimateOverride do
    let(:quote) { create(:quote) }
    let(:admin) { create(:platform_user) }

    it "can't be saved without a structured reason" do
      override = EstimateOverride.new(quote: quote, kind: "ADJUST", original_total: 1, adjusted_total: 2, actor: admin)
      expect(override).not_to be_valid
      expect(override.errors[:structured_reason]).to include("is required")
    end

    it "needs words when the reason is Other" do
      override = EstimateOverride.new(quote: quote, kind: "ADJUST", original_total: 1, adjusted_total: 2, actor: admin,
                                      structured_reason: "OTHER")
      expect(override).not_to be_valid
      override.free_text = "Agreed at the pilot rate"
      expect(override).to be_valid
    end
  end

  it "keeps a quote's events as written, and clears them with the engagement" do
    quote = create(:quote)
    event = quote.record!("proposed")
    expect { event.update!(detail: { "x" => 1 }) }.to raise_error(ActiveRecord::ReadOnlyRecord)

    expect { quote.engagement.destroy! }.to change(QuoteEvent, :count).by(-1)
  end
end
