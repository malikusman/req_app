# frozen_string_literal: true

require "nokogiri"
require "resolv"
require "ipaddr"
require "uri"
require "digest"

module Companies
  # Fetches the company website (when present), extracts readable text, summarizes,
  # and stores results as CompanyKnowledgeEntry rows with metadata.source=web_research.
  class WebResearchService
    MAX_BYTES = 500_000
    FETCH_TIMEOUT = 12
    TEXT_LIMIT = 12_000

    PRODUCT_HEADERS = {
      "User-Agent" => "WorktruthCompanyResearch/1.0 (+https://req.pebbleintelligentsolutions.com)",
      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language" => "en-US,en;q=0.9"
    }.freeze

    BROWSER_HEADERS = {
      "User-Agent" => "Mozilla/5.0 (compatible; WorktruthCompanyResearch/1.0; +https://req.pebbleintelligentsolutions.com) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language" => "en-US,en;q=0.9"
    }.freeze

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

      unless safe_public_http_url?(url)
        return { ok: false, error: "unsafe_url" }
      end

      unless @force
        fresh = @company.company_knowledge_entries
          .active
          .where("metadata->>'source' = ? AND metadata->>'url' = ?", "web_research", url)
          .where("updated_at > ?", 7.days.ago)
          .exists?
        return { ok: true, skipped: true, reason: "fresh" } if fresh
      end

      fetch = fetch_html(url)
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

    def safe_public_http_url?(url)
      uri = URI.parse(url)
      return false unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return false if uri.host.blank?

      ips = Resolv.getaddresses(uri.host)
      return false if ips.empty?

      ips.none? { |ip| private_or_loopback?(ip) }
    rescue URI::InvalidURIError, Resolv::ResolvError
      false
    end

    def private_or_loopback?(ip_str)
      ip = IPAddr.new(ip_str)
      return true if ip.loopback? || ip.private?
      return true if ip.respond_to?(:link_local?) && ip.link_local?

      # IPv4 link-local / CGNAT / metadata
      return true if ip.ipv4? && (ip.to_s.start_with?("169.254.") || ip.to_s.start_with?("100.64."))

      false
    rescue IPAddr::InvalidAddressError
      true
    end

    def fetch_html(url)
      result = get_with_headers(url, PRODUCT_HEADERS)
      if !result.success? && blocked_status?(result.status_code)
        result = get_with_headers(url, BROWSER_HEADERS)
      end

      unless result.success?
        error = if blocked_status?(result.status_code)
                  "blocked_by_site"
                else
                  result.error.presence || "fetch_failed"
                end
        return { html: nil, error: error, status_code: result.status_code, final_url: result.final_url }
      end

      body = result.body
      body = body.bytesize > MAX_BYTES ? body.byteslice(0, MAX_BYTES) : body
      { html: body, error: nil, status_code: result.status_code, final_url: result.final_url }
    end

    def get_with_headers(url, headers)
      Http::GetWithRedirects.call(
        url,
        headers: headers,
        open_timeout: FETCH_TIMEOUT,
        read_timeout: FETCH_TIMEOUT,
        validate: method(:safe_public_http_url?)
      )
    end

    def blocked_status?(code)
      [401, 403, 429].include?(code.to_i)
    end

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
