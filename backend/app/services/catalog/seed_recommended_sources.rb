# frozen_string_literal: true

module Catalog
  class SeedRecommendedSources
    RECOMMENDED = [
      {
        name: "OpenAI Blog",
        source_type: "rss",
        endpoint_url: "https://openai.com/news/rss.xml",
        trust_score: 80,
        config: { "kind" => "news", "default_entity_type" => "news", "industries" => ["software"] }
      },
      {
        name: "Google AI Blog",
        source_type: "rss",
        endpoint_url: "https://blog.google/innovation-and-ai/technology/ai/rss/",
        trust_score: 80,
        config: { "kind" => "news", "default_entity_type" => "news", "industries" => ["software"] }
      },
      {
        name: "Hugging Face Blog",
        source_type: "rss",
        endpoint_url: "https://huggingface.co/blog/feed.xml",
        trust_score: 75,
        config: { "kind" => "news", "default_entity_type" => "model", "industries" => ["software"] }
      },
      {
        name: "TechCrunch AI",
        source_type: "rss",
        endpoint_url: "https://techcrunch.com/category/artificial-intelligence/feed/",
        trust_score: 70,
        config: { "kind" => "news", "default_entity_type" => "news", "industries" => ["general"] }
      },
      {
        name: "VentureBeat AI",
        source_type: "rss",
        endpoint_url: "https://venturebeat.com/category/ai/feed",
        trust_score: 70,
        config: { "kind" => "news", "default_entity_type" => "news", "industries" => ["general"] }
      }
    ].freeze

    def self.call
      created = []
      RECOMMENDED.each do |attrs|
        source = CatalogSource.find_by(name: attrs[:name]) ||
                 CatalogSource.find_by(endpoint_url: attrs[:endpoint_url]) ||
                 CatalogSource.new
        source.assign_attributes(
          name: attrs[:name],
          source_type: attrs[:source_type],
          endpoint_url: attrs[:endpoint_url],
          trust_score: attrs[:trust_score],
          active: true,
          config: attrs[:config]
        )
        source.save!
        created << source
      end
      created
    end
  end
end
