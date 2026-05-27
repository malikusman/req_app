# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneNormalizer do
  describe ".call" do
    it "strips spaces and parentheses" do
      expect(described_class.call("(555) 123-4567")).to eq("+5551234567")
    end

    it "preserves leading plus" do
      expect(described_class.call("+1 555 123 4567")).to eq("+15551234567")
    end

    it "adds plus when missing" do
      expect(described_class.call("15551234567")).to eq("+15551234567")
    end
  end
end
