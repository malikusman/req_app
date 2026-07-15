# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::DeltaCalculator do
  let(:company) { create(:company) }

  it "returns initial summary when no previous report" do
    delta = described_class.call(company: company, previous_report: nil)
    expect(delta["summary"]).to eq("Initial discovery report").or include("Initial")
  end
end
