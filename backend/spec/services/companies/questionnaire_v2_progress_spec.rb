# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::QuestionnaireV2Progress do
  let(:keys) { Companies::QuestionnaireV2Config::FIELD_IDS }
  let(:essential_keys) { Companies::QuestionnaireV2Config::TIERS[:essential] }
  let(:non_essential_keys) { keys - essential_keys }

  it "counts only essential-tier keys as answerable" do
    result = described_class.call({})
    expect(result[:answerable_count]).to eq(essential_keys.size)
    expect(result[:completion_percent]).to eq(0)
    expect(result[:answered_count]).to eq(0)
  end

  it "ignores static display fields even if present in answers" do
    result = described_class.call(
      "msg_time_intro" => "Think about the organisation as a whole.",
      "q02_business_description" => "Freight forwarding and warehousing"
    )
    expect(result[:answered_count]).to eq(1)
    expect(result[:answerable_count]).to eq(essential_keys.size)
  end

  it "computes percent and counts from answered fields" do
    answers = essential_keys.first(5).to_h { |key| [key, "x"] }
    result = described_class.call(answers)
    expect(result[:answered_count]).to eq(5)
    expect(result[:completion_percent]).to eq(((5.0 / essential_keys.size) * 100).round)
  end

  it "treats blank strings and empty arrays as unanswered" do
    result = described_class.call(
      "q01_primary_industry" => "   ",
      "q07_departments" => []
    )
    expect(result[:answered_count]).to eq(0)
  end

  it "reports per-step section status over the 8 v2 steps" do
    step_one = Companies::QuestionnaireV2Config::STEP_FIELDS[1]
    result = described_class.call(step_one.to_h { |key| [key, "x"] })
    expect(result[:section_status].keys).to eq((1..Companies::QuestionnaireV2Config::STEP_COUNT).to_a)
    expect(result[:section_status][1]).to eq(touched: true, complete: true)
    expect(result[:section_status][2]).to eq(touched: false, complete: false)
  end

  it "reaches 100 percent when every essential field is answered" do
    result = described_class.call(essential_keys.to_h { |key| [key, "x"] })
    expect(result[:completion_percent]).to eq(100)
  end

  it "does not move the percent when only non-essential fields are answered" do
    result = described_class.call(non_essential_keys.to_h { |key| [key, "x"] })
    expect(result[:completion_percent]).to eq(0)
    expect(result[:answered_count]).to eq(0)
  end
end

RSpec.describe Companies::QuestionnaireProgress do
  describe "version-aware dispatch" do
    let(:v2_essential_keys) { Companies::QuestionnaireV2Config::TIERS[:essential] }

    it "routes version 2 companies to the v2 calculator" do
      company = build_stubbed(
        :company,
        questionnaire_version: 2,
        questionnaire_answers: v2_essential_keys.first(3).to_h { |key| [key, "x"] }
      )
      result = described_class.call_for_company(company)
      expect(result[:answerable_count]).to eq(v2_essential_keys.size)
      expect(result[:completion_percent]).to eq(((3.0 / v2_essential_keys.size) * 100).round)
    end

    it "keeps the v1 behaviour for version 1 companies" do
      company = build_stubbed(
        :company,
        questionnaire_version: 1,
        questionnaire_answers: { "company_industry" => "IT & Software", "company_size" => "11–50" }
      )
      expected = described_class::FIELD_IDS.size - 1
      expect(described_class.call_for_company(company)[:answerable_count]).to eq(expected)
    end
  end
end