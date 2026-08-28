# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::GroundedNumbers do
  def allowed(*sources)
    described_class.allowed_numbers(sources)
  end

  describe "what it lets through" do
    it "passes prose with no figures at all" do
      expect(described_class.grounded?("Approvals are slow and drag on.", allowed)).to be(true)
    end

    it "ignores bare counts, so a real tally never trips the guard" do
      # "6 issues" is not a claim about magnitude, and demanding evidence for it
      # would reject almost every summary sentence.
      expect(described_class.grounded?("We surfaced 6 issues across 3 teams.", allowed)).to be(true)
    end

    it "passes a figure that appears in the evidence" do
      set = allowed("11-14 days to pay", "target 8 days")
      expect(described_class.grounded?("Invoices take 11 days to clear.", set)).to be(true)
    end

    it "passes either end of a range stated in the evidence" do
      # Evidence stating a real range must license both bounds, or the guard deletes
      # correct sentences.
      set = allowed("11–14 days to pay")
      expect(described_class.grounded?("as long as 14 days", set)).to be(true)
      expect(described_class.grounded?("at least 11 days", set)).to be(true)
    end

    it "treats singular and plural units as the same" do
      set = allowed("takes 1 day")
      expect(described_class.grounded?("about 1 days", set)).to be(true)
    end

    it "passes a currency figure from the evidence" do
      set = allowed("AED 450,000 per year")
      expect(described_class.grounded?("worth AED 450,000 a year", set)).to be(true)
    end
  end

  describe "what it drops" do
    it "drops an invented duration" do
      set = allowed("11-14 days to pay")
      expect(described_class.grounded?("This wastes 30 hours a week.", set)).to be(false)
    end

    it "drops a real number carrying the wrong unit" do
      # The number 2 is in the evidence, but as hours. It does not license days.
      set = allowed("about 2 hours a day of rekeying")
      expect(described_class.grounded?("Approvals take 2 days.", set)).to be(false)
    end

    it "drops an invented percentage" do
      set = allowed("11-14 days to pay")
      expect(described_class.grounded?("Cuts effort by 40%.", set)).to be(false)
    end

    it "drops an invented currency figure" do
      set = allowed("AED 450,000 per year")
      expect(described_class.grounded?("saves AED 900,000", set)).to be(false)
    end

    it "drops a number outside a stated range" do
      set = allowed("11–14 days to pay")
      expect(described_class.grounded?("as long as 40 days", set)).to be(false)
    end
  end

  describe "keep_if_grounded" do
    it "returns the text when grounded and nil when not" do
      set = allowed("2 hours a day")
      expect(described_class.keep_if_grounded("about 2 hours a day", set)).to eq("about 2 hours a day")
      expect(described_class.keep_if_grounded("about 9 hours a day", set)).to be_nil
      expect(described_class.keep_if_grounded("  ", set)).to be_nil
    end
  end
end
