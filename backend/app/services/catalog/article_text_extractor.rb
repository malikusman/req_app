# frozen_string_literal: true

module Catalog
  # Best-effort HTML article text for provenance enrichment (not a general crawler).
  class ArticleTextExtractor
    def self.call(url:, max_chars: 4_000)
      new(url: url, max_chars: max_chars).call
    end

    def initialize(url:, max_chars:)
      @url = url.to_s
      @max_chars = max_chars
    end

    def call
      return "" if @url.blank?

      result = Http::GetWithRedirects.call(
        @url,
        headers: {
          "User-Agent" => "WorktruthCatalogSync/1.0",
          "Accept" => "text/html,application/xhtml+xml"
        },
        open_timeout: 5,
        read_timeout: 10
      )
      return "" unless result.success?

      body = result.body
      text = body
             .gsub(%r{<script\b[^>]*>.*?</script>}mi, " ")
             .gsub(%r{<style\b[^>]*>.*?</style>}mi, " ")
             .gsub(/<[^>]+>/, " ")
             .gsub(/&nbsp;/, " ")
             .gsub(/\s+/, " ")
             .strip
      text.truncate(@max_chars)
    rescue StandardError => e
      Rails.logger.info("[ArticleTextExtractor] skip #{@url}: #{e.message}")
      ""
    end
  end
end
