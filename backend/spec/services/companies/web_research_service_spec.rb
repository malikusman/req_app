# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::WebResearchService do
  let(:company) { create(:company, website_url: "https://example.com/about") }

  before do
    allow(Resolv).to receive(:getaddresses).and_return(["93.184.216.34"])
  end

  it "follows redirects and stores a knowledge entry" do
    html = "<html><body><main>Freight logistics and customs clearance for SMEs.</main></body></html>"
    stub_request(:get, "https://example.com/about")
      .to_return(status: 301, headers: { "Location" => "https://example.com/about-us" })
    stub_request(:get, "https://example.com/about-us")
      .to_return(status: 200, body: html)

    openai = instance_double(Openai::Client, summarize_document: { "summary" => "Logistics SME site" })
    allow(Openai::Client).to receive(:new).and_return(openai)

    result = described_class.call(company: company, force: true)

    expect(result[:ok]).to eq(true)
    expect(result[:final_url]).to eq("https://example.com/about-us")
    entry = company.company_knowledge_entries.active.last
    expect(entry.content).to eq("Logistics SME site")
    expect(entry.metadata["source"]).to eq("web_research")
    expect(entry.metadata["final_url"]).to eq("https://example.com/about-us")
  end

  it "returns blocked_by_site for hard WAF 403 responses" do
    stub_request(:get, "https://example.com/about").to_return(status: 403, body: "Access Denied")

    result = described_class.call(company: company, force: true)

    expect(result[:ok]).to eq(false)
    expect(result[:error]).to eq("blocked_by_site")
    expect(result[:status_code]).to eq(403)
  end

  it "rejects unsafe private hosts" do
    company.update!(website_url: "http://127.0.0.1/")
    allow(Resolv).to receive(:getaddresses).with("127.0.0.1").and_return(["127.0.0.1"])

    result = described_class.call(company: company, force: true)

    expect(result[:ok]).to eq(false)
    expect(result[:error]).to eq("unsafe_url")
  end
end
