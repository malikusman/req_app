# frozen_string_literal: true

require "rails_helper"

RSpec.describe Intelligence::RecommendationSynthesizer do
  let(:company) do
    create(:company, settings: {
      "agent_features" => { "opportunity_scout" => true }
    })
  end

  let(:client) { instance_double(Langgraph::Client) }

  before do
    allow(Langgraph::Client).to receive(:new).and_return(client)
    allow(client).to receive(:create_thread!).and_return("thread-scout-1")
  end

  describe "opportunity scout with HITL" do
    it "creates an interrupt when high-impact opportunities lack platform approval" do
      allow(client).to receive(:scout_opportunities!).and_return(
        "opportunities" => [{
          "title" => "Automate invoice processing",
          "description" => "Eliminate manual spreadsheet work",
          "impact" => "high",
          "effort" => "low",
          "timeframe" => "quick_win",
          "benefit_summary" => "Save 10 hours per week",
          "suggested_tools" => ["Zapier"],
          "evidence" => []
        }]
      )

      result = nil
      expect {
        result = described_class.call(company: company)
      }.to change(AgentInterrupt, :count).by(1)

      expect(result).to eq([])
      interrupt = AgentInterrupt.last
      expect(interrupt.kind).to eq("opportunity_recommendation")
      expect(interrupt.payload["recommendations"].size).to eq(1)
    end

    it "returns recommendations directly when impact is medium and evidence present" do
      allow(client).to receive(:scout_opportunities!).and_return(
        "opportunities" => [{
          "title" => "Improve team collaboration",
          "description" => "Standardize handoffs",
          "impact" => "medium",
          "effort" => "medium",
          "timeframe" => "medium_term",
          "benefit_summary" => "Fewer delays",
          "suggested_tools" => [],
          "evidence" => [{ "type" => "signal", "id" => 1, "summary" => "approval delay" }]
        }]
      )

      result = described_class.call(company: company)

      expect(result.size).to eq(1)
      expect(result.first[:source]).to eq("opportunity_scout")
      expect(AgentInterrupt.count).to eq(0)
    end
  end
end
