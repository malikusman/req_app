# frozen_string_literal: true

require "nokogiri"
require "digest"

module Companies
  # Fetches the company website (when present), extracts readable text, summarizes,
  # and stores results as CompanyKnowledgeEntry rows with metadata.source=web_research.
  class WebResearchService
    TEXT_LIMIT = 12_000

    def self.call(company:, force: false)
      new(company: company, force: force).call
    end

    def initialize(company:, force: false)
      @company = company
      @force = force
    end

    def call
      url = @company.website_url.to_s.strip.presence
      return { ok: false, error: "no_website_url" } if url.blank?

      return { ok: false, error: "unsafe_url" } unless WebsiteFetcher.safe_public_http_url?(url)

      unless @force
        fresh = @company.company_knowledge_entries
          .active
          .where("metadata->>'source' = ? AND metadata->>'url' = ?", "web_research", url)
          .where("updated_at > ?", 7.days.ago)
          .exists?
        return { ok: true, skipped: true, reason: "fresh" } if fresh
      end

      fetch = WebsiteFetcher.new.fetch_html(url)
      return { ok: false, error: fetch[:error], status_code: fetch[:status_code], final_url: fetch[:final_url] } if fetch[:html].blank?

      text = extract_text(fetch[:html])
      return { ok: false, error: "empty_content", final_url: fetch[:final_url] } if text.blank?

      summary = summarize(text, fetch[:final_url] || url)
      entry = persist_entry!(url: url, summary: summary, raw_excerpt: text.truncate(2000), final_url: fetch[:final_url])
      { ok: true, entry_id: entry.id, url: url, final_url: fetch[:final_url] }
    rescue StandardError => e
      Rails.logger.warn("[WebResearchService] company=#{@company.id} #{e.class}: #{e.message}")
      { ok: false, error: e.message }
    end

    private

    def extract_text(html)
      doc = Nokogiri::HTML(html)
      doc.css("script, style, noscript, nav, footer, header").remove
      text = doc.at("main")&.text || doc.at("body")&.text || doc.text
      text.to_s.gsub(/\s+/, " ").strip.truncate(TEXT_LIMIT)
    end

    def summarize(text, url)
      client = Openai::Client.new
      insights = client.summarize_document(
        "Company website (#{url}):\n#{text.truncate(10_000)}",
        language: "en"
      )
      summary = insights.is_a?(Hash) ? insights["summary"].presence : nil
      summary.presence || text.truncate(600)
    rescue StandardError => e
      Rails.logger.warn("[WebResearchService] summarize failed: #{e.message}")
      text.truncate(600)
    end

    def persist_entry!(url:, summary:, raw_excerpt:, final_url: nil)
      title = "Website research: #{@company.display_name || @company.name}"
      content_hash = Digest::SHA256.hexdigest("#{url}|#{summary}")[0, 32]

      existing = @company.company_knowledge_entries
        .active
        .where("metadata->>'source' = ? AND metadata->>'url' = ?", "web_research", url)
        .order(updated_at: :desc)
        .first

      attrs = {
        entry_type: "org",
        title: title,
        content: summary.presence || raw_excerpt,
        confidence: 0.7,
        content_hash: content_hash,
        metadata: {
          "source" => "web_research",
          "url" => url,
          "final_url" => final_url,
          "fetched_at" => Time.current.iso8601,
          "raw_excerpt" => raw_excerpt
        }
      }

      if existing
        existing.update!(attrs)
        existing
      else
        @company.company_knowledge_entries.create!(attrs.merge(status: "active"))
      end
    end
  end
end
