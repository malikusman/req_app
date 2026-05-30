# frozen_string_literal: true

require "rails_helper"

RSpec.describe Knowledge::IndexProfileService do
  let(:company) do
    create(:company, profile_context: {
      "basics" => {
        "industry" => "technology",
        "company_size_band" => "51-200",
        "hq_country" => "US",
        "one_line_description" => "Indexed Co"
      },
      "strategy" => {
        "top_priorities" => ["growth"],
        "transformation_goals" => ["automation"],
        "digital_vision_maturity" => "emerging",
        "success_metrics" => ["efficiency"]
      }
    })
  end

  before do
    allow_any_instance_of(Openai::Client).to receive(:embedding).and_return(Array.new(1536, 0.01))
  end

  it "indexes per-section and full profile chunks" do
    expect {
      described_class.call(company: company)
    }.to change(KnowledgeChunk, :count).by_at_least(2)

    basics = KnowledgeChunk.find_by(company: company, source_type: "profile_section", source_id: 1)
    expect(basics).to be_present
    expect(basics.content).to include("technology")

    full = KnowledgeChunk.find_by(company: company, source_type: "profile_section", source_id: company.id)
    expect(full).to be_present
  end
end
