# frozen_string_literal: true

require "rails_helper"

RSpec.describe Knowledge::SemanticSearch do
  let(:company) { create(:company) }

  it "returns empty array for blank query" do
    expect(described_class.call(company: company, query: "")).to eq([])
  end
end
