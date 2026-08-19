# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::QuestionnaireV2Config do
  it "registers the 45 stored v2 keys with no duplicates" do
    expect(described_class::FIELD_IDS.size).to eq(45)
    expect(described_class::FIELD_IDS.uniq.size).to eq(45)
  end

  it "groups the 45 keys into 8 steps" do
    expect(described_class::STEP_FIELDS.keys).to eq((1..8).to_a)
    expect(described_class::STEP_FIELDS.values.flatten.size).to eq(45)
    expect(described_class::STEP_FIELDS.values.flatten.uniq.size).to eq(45)
    expect(described_class::STEP_COUNT).to eq(8)
  end

  it "includes the lettered sub-questions" do
    %w[q10a_documentation_types q10b_certifications q25a_manual_movement_example q37a_ai_training].each do |key|
      expect(described_class::FIELD_IDS).to include(key)
    end
  end

  it "tallies tiers as 29 essential, 8 recommended, 7 optional, 1 conditional" do
    expect(described_class::TIERS[:essential].size).to eq(29)
    expect(described_class::TIERS[:recommended].size).to eq(8)
    expect(described_class::TIERS[:optional].size).to eq(7)
    expect(described_class::TIERS[:conditional].size).to eq(1)
  end

  it "assigns a tier to every registered key" do
    expect(described_class::TIERS_BY_KEY.keys).to match_array(described_class::FIELD_IDS)
    described_class::FIELD_IDS.each do |key|
      expect(%i[essential recommended optional conditional]).to include(described_class::TIERS_BY_KEY[key])
    end
  end
end