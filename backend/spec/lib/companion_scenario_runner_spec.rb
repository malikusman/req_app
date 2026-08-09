# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/companion_scenario_runner")

RSpec.describe CompanionScenarioRunner do
  it "defines the expected scenario matrix" do
    runner = described_class.new(live: false, write: false)
    ids = runner.send(:scenarios).map(&:id)
    expect(ids).to eq(%w[C1 C2 C3 C7 C4 C5 C6 W1])
  end
end
