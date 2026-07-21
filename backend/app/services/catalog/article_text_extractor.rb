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

      uri = URI.parse(@url)
      return "" unless uri.is_a?(URI::HTTP)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "WorktruthCatalogSync/1.0"
        req["Accept"] = "text/html,application/xhtml+xml"
        http.request(req)
      end
      return "" unless response.is_a?(Net::HTTPSuccess)

      body = response.body.to_s
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
