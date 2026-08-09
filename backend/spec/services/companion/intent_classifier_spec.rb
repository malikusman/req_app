# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companion::IntentClassifier do
  it "classifies explicit addendum phrases" do
    result = described_class.call(text: "Please add this to my interview")
    expect(result[:intent]).to eq("addendum")
    expect(result[:confidence]).to be >= 0.85
  end

  it "classifies tools intent" do
    result = described_class.call(text: "Any new tools for invoice matching?")
    expect(result[:intent]).to eq("tools")
  end

  it "returns promote_confirm when awaiting and user affirms" do
    result = described_class.call(text: "yes please", awaiting_promote_confirm: true)
    expect(result[:intent]).to eq("promote_confirm")
  end

  it "fail-safes short casual text" do
    result = described_class.call(text: "thanks!")
    expect(result[:intent]).to eq("casual")
  end
end
