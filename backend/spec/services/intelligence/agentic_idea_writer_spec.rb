# frozen_string_literal: true

require "rails_helper"

RSpec.describe Intelligence::AgenticIdeaWriter do
  let(:company) { create(:company) }
  let!(:signal) do
    create(:company_signal, company: company, label: "Manual invoice entry", strength: 0.8,
                            departments: ["finance"], signal_type: "manual_process")
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("AI_AGENTIC_IDEAS", "true").and_return("true")
  end

  def stub_client(configured:, payload: nil)
    client = instance_double(Openai::Client, configured?: configured)
    allow(client).to receive(:agentic_ideas).and_return(payload) if payload
    allow(Openai::Client).to receive(:new).and_return(client)
  end

  it "returns nil (fallback) when the client is not configured" do
    stub_client(configured: false)
    expect(described_class.call(company: company)).to be_nil
  end

  it "returns nil when disabled by env flag" do
    stub_client(configured: true)
    allow(ENV).to receive(:fetch).with("AI_AGENTIC_IDEAS", "true").and_return("false")
    expect(described_class.call(company: company)).to be_nil
  end

  it "maps a valid LLM payload into upsert-ready ideas with signal linkage" do
    stub_client(configured: true, payload: {
      "ideas" => [{
        "title" => "AP Copilot",
        "summary" => "Drafts SAP entries from invoices.",
        "addresses_signals" => ["Manual invoice entry"],
        "system_fit" => "Extends SAP.",
        "value_time" => "Less re-keying.", "value_efficiency" => "Fewer handoffs.",
        "value_cost" => "Fewer exceptions.", "effort" => "M", "confidence" => 0.72
      }]
    })

    ideas = described_class.call(company: company)
    expect(ideas.size).to eq(1)
    idea = ideas.first
    expect(idea[:title]).to eq("AP Copilot")
    expect(idea[:related_signal_ids]).to eq([signal.id])
    expect(idea[:confidence]).to eq(0.72)
    expect(idea[:source]).to eq("generated")
    expect(idea[:status]).to eq("draft")
  end

  it "returns nil when the payload has no ideas" do
    stub_client(configured: true, payload: { "ideas" => [] })
    expect(described_class.call(company: company)).to be_nil
  end

  it "produces upsert-compatible ideas that persist as draft agentic ideas" do
    stub_client(configured: true, payload: {
      "ideas" => [{ "title" => "AP Copilot", "summary" => "x", "addresses_signals" => ["Manual invoice entry"], "confidence" => 0.7 }]
    })
    ideas = described_class.call(company: company)
    records = Intelligence::AgenticIdeaUpsertService.call(company: company, ideas: ideas)
    expect(records.map(&:title)).to include("AP Copilot")
    expect(records.first.status).to eq("draft")
  end
end
