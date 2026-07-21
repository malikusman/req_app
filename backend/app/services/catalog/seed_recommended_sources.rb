# frozen_string_literal: true

module Catalog
  class SeedRecommendedSources
    RECOMMENDED = [
      {
        name: "OpenAI Blog",
        source_type: "rss",
        endpoint_url: "https://openai.com/blog/rss.xml",
        trust_score: 80,
        config: { "kind" => "news", "default_entity_type" => "news", "industries" => ["software"] }
      },
      {
        name: "Google AI Blog",
        source_type: "rss",
        endpoint_url: "https://blog.google/technology/ai/rss/",
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
        endpoint_url: "https://venturebeat.com/category/ai/feed/",
        trust_score: 70,
        config: { "kind" => "news", "default_entity_type" => "news", "industries" => ["general"] }
      }
    ].freeze

    def self.call
      created = []
      RECOMMENDED.each do |attrs|
        source = CatalogSource.find_or_initialize_by(endpoint_url: attrs[:endpoint_url])
        source.assign_attributes(
          name: attrs[:name],
          source_type: attrs[:source_type],
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
