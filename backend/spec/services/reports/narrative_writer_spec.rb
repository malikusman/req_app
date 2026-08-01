# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::NarrativeWriter do
  let(:company) { create(:company) }
  let(:snapshot) do
    {
      "company" => { "name" => "Acme", "profile" => { "industry" => "logistics" } },
      "report_kind" => "discovery",
      "participation" => { "invited" => 4, "completed" => 3 },
      "signals" => [{ "label" => "Manual invoice entry", "strength" => 0.8, "departments" => ["finance"] }],
      "patterns" => [{ "title" => "Approval bottleneck", "confidence" => 0.7, "linked_signal_labels" => ["Manual invoice entry"] }],
      "recommendations" => [{ "title" => "Automate intake", "priority" => "high", "impact_score" => 1.0, "feasibility_score" => 0.6 }],
      "implications" => [{ "title" => "Approval bottleneck", "statement" => "deterministic fallback statement" }],
      "supporting_documents" => []
    }
  end

  # The suite disables the narrative by default (see spec/support/report_narrative.rb);
  # these examples opt back in.
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("AI_REPORT_NARRATIVE", "true").and_return("true")
  end

  def stub_client(configured:, payload: nil)
    client = instance_double(Openai::Client, configured?: configured)
    allow(client).to receive(:report_narrative).and_return(payload) if payload
    allow(Openai::Client).to receive(:new).and_return(client)
    client
  end

  it "returns nil (deterministic fallback) when the client is not configured" do
    stub_client(configured: false)
    expect(described_class.call(company: company, snapshot: snapshot)).to be_nil
  end

  it "returns nil when disabled by env flag" do
    stub_client(configured: true)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("AI_REPORT_NARRATIVE", "true").and_return("false")
    expect(described_class.call(company: company, snapshot: snapshot)).to be_nil
  end

  it "normalizes a valid LLM payload into narrative structure" do
    stub_client(configured: true, payload: {
      "governing_thought" => "Manual approvals are the primary drag.",
      "executive_summary" => "Evidence shows manual effort and approval delay dominate.",
      "supporting_points" => ["a", "b", "", "c", "d", "e"],
      "stakes" => "Compounds with volume.",
      "implications" => [{ "pattern_title" => "Approval bottleneck", "statement" => "LLM so-what" }],
      "roadmap" => { "now" => [{ "title" => "Fix approval", "rationale" => "quick win" }], "next" => [], "later" => [] }
    })

    result = described_class.call(company: company, snapshot: snapshot)
    expect(result["governing_thought"]).to eq("Manual approvals are the primary drag.")
    expect(result["supporting_points"].size).to eq(4)
    expect(result["roadmap"]["now"].first["title"]).to eq("Fix approval")
    expect(result["generated_by"]).to eq("llm")
  end

  it "returns nil when the payload has no usable summary" do
    stub_client(configured: true, payload: { "supporting_points" => ["x"] })
    expect(described_class.call(company: company, snapshot: snapshot)).to be_nil
  end

  it "swallows client errors and falls back" do
    client = instance_double(Openai::Client, configured?: true)
    allow(client).to receive(:report_narrative).and_raise(Openai::Client::Error, "boom")
    allow(Openai::Client).to receive(:new).and_return(client)
    expect(described_class.call(company: company, snapshot: snapshot)).to be_nil
  end
end
