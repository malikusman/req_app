# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::QuestionnaireProgress do
  it "excludes ai_tools_used when AI usage is not yet" do
    result = described_class.call("current_ai_usage" => "No, not yet")
    expect(result[:answerable_count]).to eq(Companies::QuestionnaireProgress::FIELD_IDS.size - 1)
  end

  it "includes ai_tools_used when AI is in use" do
    result = described_class.call("current_ai_usage" => "Yes, occasionally (e.g., ChatGPT for individual tasks)")
    expect(result[:answerable_count]).to eq(Companies::QuestionnaireProgress::FIELD_IDS.size)
  end

  it "computes percent from answered fields" do
    result = described_class.call(
      "company_industry" => "IT & Software",
      "company_size" => "11–50"
    )
    expect(result[:answered_count]).to eq(2)
    expect(result[:completion_percent]).to be_between(1, 99)
  end
end
