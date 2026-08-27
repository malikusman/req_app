# frozen_string_literal: true

require "rails_helper"

RSpec.describe Consultants::QuestionnaireProgress do
  it "counts experience rows with org and title" do
    result = described_class.call(
      {
        "experiences" => [{ "organization" => "Acme", "title" => "Lead" }],
        "headline" => "Hello"
      }
    )
    expect(result[:answered_count]).to be >= 2
  end
end
