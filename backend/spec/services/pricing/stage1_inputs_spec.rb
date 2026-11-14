# frozen_string_literal: true

require "rails_helper"

# What the Stage 1 fee is calculated from (Doc 17 §2.2): the engagement's plan
# and the company's confirmed facts, with the administrator's corrections.
RSpec.describe Pricing::Stage1Inputs do
  let(:company) do
    create(:company, company_profile: { "country" => "United Arab Emirates", "locations" => ["Dubai", "Abu Dhabi", ""],
                                        "industry" => "wholesale_distribution", "size_band" => "51-200" })
  end
  let(:engagement) do
    create(:engagement, company: company, status: "STAGE_1_PRICING", languages: %w[en ar],
                        planned_departments: [{ "name" => "Sales", "count" => 2 }, { "name" => "Finance", "count" => 1 }])
  end

  before do
    create(:engagement_participant, engagement: engagement, participant_type: "EMPLOYEE", name: "Shiv")
    create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Huda")
    create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Omar",
                                    participation_status: "DECLINED")
  end

  it "reads the plan, the people named so far and the company's facts" do
    inputs = described_class.from(engagement)

    expect(inputs.to_h).to include("participants" => 3, "key_persons" => 1, "named_participants" => 1,
                                   "languages" => %w[en ar], "locations" => 2, "country" => "AE", "deep_dives" => nil,
                                   "industry" => "wholesale_distribution")
    expect(inputs.sources).to eq("deep_dives" => "ENGAGEMENT", "locations" => "ENGAGEMENT", "country" => "ENGAGEMENT")
  end

  it "takes an administrator's corrections, and says so" do
    inputs = described_class.from(engagement, deep_dives: "4", locations: "1", country: "KSA", participants: 99)

    expect(inputs.to_h).to include("deep_dives" => 4, "locations" => 1, "country" => "SA", "participants" => 3)
    expect(inputs.sources).to include("deep_dives" => "ADMINISTRATOR", "country" => "ADMINISTRATOR")
  end

  it "rebuilds a quote's inputs with new corrections on top" do
    stored = JSON.parse(described_class.from(engagement, locations: 1).to_h.to_json)
    rebuilt = described_class.from_h(stored, deep_dives: "5")

    expect(rebuilt.to_h).to include("deep_dives" => 5, "locations" => 1, "participants" => 3)
    expect(rebuilt.sources).to include("locations" => "ADMINISTRATOR", "deep_dives" => "ADMINISTRATOR")
  end

  it "recognises a country however it was typed" do
    expect(["UAE", "united arab emirates", "Saudi Arabia", "qa", "Not sure", "", "Atlantis"].map { |c| described_class.country_code(c) })
      .to eq(["AE", "AE", "SA", "QA", nil, nil, "Atlantis"])
  end
end
