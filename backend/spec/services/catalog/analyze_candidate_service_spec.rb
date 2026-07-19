# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::AnalyzeCandidateService do
  before do
    client = instance_double(Openai::Client, configured?: false)
    allow(Openai::Client).to receive(:new).and_return(client)
  end

  let(:source) do
    CatalogSource.create!(
      name: "News RSS",
      source_type: "rss",
      endpoint_url: "https://example.com/feed.xml",
      active: true,
      trust_score: 0.7,
      config: { "kind" => "news", "default_entity_type" => "news" }
    )
  end

  let(:record) do
    CatalogSourceRecord.create!(
      catalog_source: source,
      external_id: "item-1",
      fingerprint: SecureRandom.hex(16),
      title: "Finance automation launches",
      url: "https://example.com/article",
      fetched_at: Time.current,
      parse_status: "parsed",
      raw_payload: {
        "description" => "AP automation for finance teams",
        "published_at" => published_at.iso8601
      }
    )
  end

  let(:candidate) do
    CatalogCandidate.create!(
      catalog_source_record: record,
      name: "Finance automation launches",
      entity_type: "tool",
      description: "AP automation for finance teams",
      website_url: "https://example.com/article",
      confidence: 0.4,
      review_status: "pending",
      analysis_status: "pending",
      provenance: { "source_url" => "https://example.com/article", "stub" => false }
    )
  end

  context "when published recently" do
    let(:published_at) { 2.days.ago }

    it "marks the candidate analyzed with news entity type" do
      result = described_class.call(candidate: candidate)

      expect(result.analysis_status).to eq("analyzed")
      expect(result.entity_type).to eq("news")
      expect(result.summary).to be_present
      expect(result.analyzed_at).to be_present
    end
  end

  context "when published beyond news max age" do
    let(:published_at) { 30.days.ago }

    it "marks the candidate stale" do
      result = described_class.call(candidate: candidate)
      expect(result.analysis_status).to eq("stale")
    end
  end
end
