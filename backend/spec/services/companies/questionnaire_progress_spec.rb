# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::QuestionnaireProgress do
  Config = Companies::QuestionnaireConfig

  describe "what counts" do
    # The client was explicit: Recommended and Optional questions are worth asking
    # but must never hold someone at 99%.
    it "counts only Essential questions" do
      result = described_class.call({})

      expect(result[:answerable_count]).to eq(Config::ESSENTIAL_KEYS.size)
      expect(result[:answerable_count]).to be < Config::FIELD_IDS.size
    end

    it "reaches 100 once the Essential questions are answered, with everything else blank" do
      answers = Config::ESSENTIAL_KEYS.to_h { |k| [k, "answered"] }

      expect(described_class.call(answers)[:completion_percent]).to eq(100)
    end

    it "ignores an Optional answer in the percent" do
      optional = Config::FIELDS.find { |f| f[:tier] == :optional }[:key]

      result = described_class.call(optional => "something")

      expect(result[:answered_count]).to eq(0)
      expect(result[:completion_percent]).to eq(0)
    end
  end

  describe "conditional questions" do
    # Q10a is not Essential, so it never counts — but visibility still has to be
    # right, because the steps report it and the frontend mirrors this logic.
    it "hides the documentation follow-up when there is no documentation" do
      answers = { "q10_process_documentation" => "We do not have formal process documentation" }

      expect(Config.visible?("q10a_documentation_types", answers)).to be(false)
    end

    it "shows it once documentation exists" do
      answers = { "q10_process_documentation" => "Some processes are documented" }

      expect(Config.visible?("q10a_documentation_types", answers)).to be(true)
    end

    it "keeps it hidden while the question it depends on is unanswered" do
      expect(Config.visible?("q10a_documentation_types", {})).to be(false)
    end
  end

  describe "answered?" do
    # The matrix questions store a keyed map, so the old "string or array" test
    # would have read every one of them as unanswered.
    it "reads a filled matrix answer as answered" do
      result = described_class.call("q29_external_parties_channels" => { "customers / clients" => ["email"] })

      expect(result[:section_status][5][:touched]).to be(true)
    end

    it "reads a matrix with only empty rows as unanswered" do
      result = described_class.call("q29_external_parties_channels" => { "customers / clients" => [] })

      expect(result[:section_status][5][:touched]).to be(false)
    end

    it "does not count whitespace as an answer" do
      result = described_class.call(Config::ESSENTIAL_KEYS.first => "   ")

      expect(result[:answered_count]).to eq(0)
    end
  end

  describe "step status" do
    it "reports all eight steps" do
      expect(described_class.call({})[:section_status].keys).to eq((1..8).to_a)
    end

    # Touch and completeness are different questions: someone who answered only the
    # optional question in a step has still been there.
    it "marks a step touched by an optional answer but not complete" do
      optional = Config::FIELDS.find { |f| f[:tier] == :optional }
      status = described_class.call(optional[:key] => "noted")[:section_status][optional[:step]]

      expect(status[:touched]).to be(true)
      expect(status[:complete]).to be(false)
    end

    it "marks a step complete once its Essential questions are answered" do
      step_one = Config::FIELDS.select { |f| f[:step] == 1 && f[:tier] == :essential }
      answers = step_one.to_h { |f| [f[:key], "answered"] }

      expect(described_class.call(answers)[:section_status][1][:complete]).to be(true)
    end
  end
end
