# frozen_string_literal: true

module Catalog
  # Classifies and enriches a market candidate (tool / news / model) after ingest.
  class AnalyzeCandidateService
    NEWS_MAX_AGE_DAYS = ENV.fetch("AI_MARKET_NEWS_MAX_AGE_DAYS", "14").to_i

    def self.call(candidate:)
      new(candidate: candidate).call
    end

    def initialize(candidate:)
      @candidate = candidate
      @record = candidate.catalog_source_record
    end

    def call
      payload = analyze_payload
      status = freshness_status(payload[:published_at])

      @candidate.update!(
        entity_type: payload[:entity_type],
        summary: payload[:summary],
        industries: payload[:industries],
        topics: payload[:topics],
        confidence: payload[:confidence],
        published_at: payload[:published_at],
        analysis_status: status,
        analyzed_at: Time.current,
        description: @candidate.description.presence || payload[:summary]
      )
      @candidate
    end

    private

    def analyze_payload
      text = corpus
      if Openai::Client.new.configured?
        llm_analyze(text)
      else
        rule_analyze(text)
      end
    rescue StandardError => e
      Rails.logger.warn("[AnalyzeCandidate] LLM failed candidate=#{@candidate.id}: #{e.message}")
      rule_analyze(corpus)
    end

    def corpus
      parts = [
        @candidate.name,
        @candidate.description,
        @candidate.summary,
        @record&.title,
        @record&.raw_payload&.dig("description"),
        @record&.raw_payload&.dig("article_text")
      ]
      parts.compact.map(&:to_s).join("\n").truncate(8_000)
    end

    def llm_analyze(text)
      client = Openai::Client.new
      # Reuse summarize_document-style JSON via understand_document_structured when available
      raw = if client.respond_to?(:understand_document_structured)
              client.understand_document_structured(text: analysis_prompt(text), language: "en")
            else
              {}
            end

      entity = infer_entity_type("#{raw['summary']} #{text}")
      published = parse_time(@record&.raw_payload&.dig("published_at")) || @candidate.published_at || @record&.fetched_at

      {
        entity_type: entity,
        summary: raw["summary"].presence || text.to_s.truncate(280),
        industries: Array(raw["workflows"]).first(5).presence || infer_industries(text),
        topics: (Array(raw["friction_points"]) + Array(raw["tools_mentioned"])).map(&:to_s).first(8).presence || infer_topics(text),
        confidence: raw["confidence"].presence || 0.65,
        published_at: published
      }
    end

    def rule_analyze(text)
      {
        entity_type: infer_entity_type(text),
        summary: text.to_s.gsub(/\s+/, " ").strip.truncate(280),
        industries: infer_industries(text),
        topics: infer_topics(text),
        confidence: @candidate.confidence.presence || 0.45,
        published_at: parse_time(@record&.raw_payload&.dig("published_at")) || @candidate.published_at || @record&.fetched_at
      }
    end

    def analysis_prompt(text)
      <<~TXT
        Classify this AI market item for an enterprise discovery platform.
        Prefer entity types: tool, news, model, or other.
        Text:
        #{text}
      TXT
    end

    def infer_entity_type(text)
      t = text.to_s.downcase
      return "model" if t.match?(/\b(gpt|claude|llama|gemini|mistral|foundation model|llm)\b/)
      return "news" if t.match?(/\b(news|announce|launches|released|blog|funding|raises)\b/)
      return "tool" if t.match?(/\b(tool|platform|saas|copilot|automation|product)\b/)

      source_type = @record&.catalog_source&.source_type
      config_type = @record&.catalog_source&.config&.dig("default_entity_type")
      return config_type if CatalogCandidate::ENTITY_TYPES.include?(config_type.to_s)

      source_type == "rss" && @record&.catalog_source&.config&.dig("kind") == "news" ? "news" : "tool"
    end

    def infer_industries(text)
      map = {
        "finance" => /\b(finance|invoice|erp|sap|banking)\b/i,
        "healthcare" => /\b(health|clinical|hospital|pharma)\b/i,
        "manufacturing" => /\b(manufactur|supply chain|factory|industrial)\b/i,
        "software" => /\b(developer|saas|devops|software|ai)\b/i
      }
      hits = map.select { |_k, rx| text.match?(rx) }.keys
      hits.presence || ["general"]
    end

    def infer_topics(text)
      topics = []
      topics << "automation" if text.match?(/automat/i)
      topics << "llm" if text.match?(/\b(llm|gpt|generative)\b/i)
      topics << "workflow" if text.match?(/workflow|process/i)
      topics << "integration" if text.match?(/integrat|api/i)
      topics.presence || ["ai"]
    end

    def freshness_status(published_at)
      return "analyzed" if published_at.blank?

      max_age = NEWS_MAX_AGE_DAYS.positive? ? NEWS_MAX_AGE_DAYS : 14
      published_at < max_age.days.ago ? "stale" : "analyzed"
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
