# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SyncSourceService do
  let(:source) do
    CatalogSource.create!(
      name: "Test RSS",
      source_type: "rss",
      endpoint_url: "https://example.com/feed.xml",
      active: true,
      trust_score: 0.5
    )
  end

  it "parses RSS items into candidates when endpoint returns a feed" do
    feed = <<~XML
      <?xml version="1.0"?>
      <rss><channel>
        <item>
          <title><![CDATA[Acme Invoice AI]]></title>
          <link>https://example.com/acme</link>
          <description><![CDATA[<p>AP automation for SAP</p>]]></description>
        </item>
        <item>
          <title>Beta Close Copilot</title>
          <link>https://example.com/beta</link>
          <description>Month-end close helper</description>
        </item>
      </channel></rss>
    XML

    stub_request(:get, "https://example.com/feed.xml").to_return(status: 200, body: feed, headers: { "Content-Type" => "application/rss+xml" })

    run = described_class.call(catalog_source: source)

    expect(run.status).to eq("success")
    expect(run.candidates_created).to eq(2)
    names = CatalogCandidate.order(:id).pluck(:name)
    expect(names).to include("Acme Invoice AI", "Beta Close Copilot")
    expect(CatalogCandidate.find_by(name: "Acme Invoice AI").description).to include("AP automation")
  end

  it "uses stub candidates when no endpoint is configured" do
    source.update!(endpoint_url: nil)
    run = described_class.call(catalog_source: source)
    expect(run.candidates_created).to eq(1)
    expect(CatalogCandidate.last.provenance["stub"]).to eq(true)
  end
end

RSpec.describe CatalogSyncSchedule do
  it "builds cron from AI_CATALOG_SYNC_INTERVAL_HOURS" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("AI_CATALOG_SYNC_INTERVAL_HOURS", "12").and_return("6")
    expect(described_class.interval_hours).to eq(6)
    expect(described_class.cron_expression).to eq("0 */6 * * *")
  end
end
