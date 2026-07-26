# frozen_string_literal: true

require "net/http"
require "digest"
require "json"

module Catalog
  class SyncSourceService
    DEFAULT_BUDGET = 25

    def self.call(catalog_source:)
      new(catalog_source: catalog_source).call
    end

    def initialize(catalog_source:)
      @source = catalog_source
      @budget = ENV.fetch("AI_CATALOG_MAX_CANDIDATES_PER_RUN", DEFAULT_BUDGET.to_s).to_i
      @budget = DEFAULT_BUDGET if @budget <= 0
    end

    def call
      run = CatalogSyncRun.create!(
        catalog_source: @source,
        started_at: Time.current,
        status: "running",
        budget: { "max_candidates" => @budget }
      )

      items = fetch_items
      run.update!(records_fetched: items.size)

      created = 0
      errors = []

      items.each do |item|
        break if created >= @budget

        begin
          fingerprint = Digest::SHA256.hexdigest(item[:content].to_s)
          existing = CatalogSourceRecord.find_by(catalog_source: @source, fingerprint: fingerprint)
          next if existing

          record = CatalogSourceRecord.create!(
            catalog_source: @source,
            catalog_sync_run: run,
            external_id: item[:external_id],
            fingerprint: fingerprint,
            title: item[:title],
            url: item[:url],
            raw_payload: item[:raw] || {},
            fetched_at: Time.current,
            parse_status: "parsed"
          )

          candidate = CatalogCandidate.create!(
            catalog_source_record: record,
            name: item[:title].presence || "Untitled candidate",
            vendor: item[:vendor],
            entity_type: item[:entity_type].presence || default_entity_type,
            description: item[:description],
            website_url: item[:url],
            confidence: item[:confidence] || 0.4,
            review_status: "pending",
            analysis_status: "pending",
            published_at: item[:published_at],
            provenance: {
              "catalog_source_id" => @source.id,
              "catalog_source_name" => @source.name,
              "catalog_sync_run_id" => run.id,
              "source_url" => item[:url],
              "fingerprint" => fingerprint,
              "fetched_at" => Time.current.iso8601,
              "stub" => item[:raw].is_a?(Hash) && item[:raw]["stub"] == true
            }
          )
          created += 1
          AnalyzeCatalogCandidateJob.perform_later(candidate.id)
        rescue StandardError => e
          errors << { "external_id" => item[:external_id], "error" => e.message }
        end
      end

      status = if errors.any? && created.positive?
                 "partial"
               elsif errors.any?
                 "failed"
               else
                 "success"
               end

      run.update!(
        finished_at: Time.current,
        status: status,
        candidates_created: created,
        error_details: errors
      )
      @source.update!(last_sync_at: Time.current, last_sync_status: status)
      run
    rescue StandardError => e
      run&.update!(finished_at: Time.current, status: "failed", error_details: [{ "error" => e.message }])
      @source.update!(last_sync_at: Time.current, last_sync_status: "failed")
      raise
    end

    private

    def fetch_items
      if @source.endpoint_url.blank?
        stub_items
      elsif @source.source_type == "api"
        fetch_from_api
      else
        fetch_from_endpoint
      end
    end

    def default_entity_type
      configured = @source.config.is_a?(Hash) && @source.config["default_entity_type"].to_s
      CatalogCandidate::ENTITY_TYPES.include?(configured) ? configured : "tool"
    end

    def fetch_from_api
      result = Http::GetWithRedirects.call(
        @source.endpoint_url,
        headers: {
          "User-Agent" => "WorktruthCatalogSync/1.0",
          "Accept" => "application/json"
        },
        open_timeout: 10,
        read_timeout: 20
      )
      raise "HTTP fetch failed: #{result.error}" unless result.success?

      parse_api_json(result.body)
    end

    def parse_api_json(body)
      parsed = JSON.parse(body)
      rows = if parsed.is_a?(Array)
               parsed
             elsif parsed.is_a?(Hash)
               parsed["items"] || parsed["results"] || parsed["data"] || []
             else
               []
             end
      Array(rows).first(@budget).map.with_index do |row, index|
        row = row.with_indifferent_access if row.respond_to?(:with_indifferent_access)
        title = row["title"] || row["name"] || "API item #{index + 1}"
        link = row["url"] || row["link"] || row["website_url"]
        description = row["description"] || row["summary"] || ""
        candidate_hash(
          title: title,
          link: link,
          description: description,
          content: row.to_json,
          confidence: 0.55,
          published_at: row["published_at"] || row["publishedAt"] || row["created_at"],
          entity_type: row["entity_type"] || default_entity_type
        )
      end
    rescue JSON::ParserError
      parse_feed(body)
    end

    def fetch_from_endpoint
      result = Http::GetWithRedirects.call(
        @source.endpoint_url,
        headers: {
          "User-Agent" => "WorktruthCatalogSync/1.0",
          "Accept" => "application/rss+xml, application/atom+xml, application/xml, text/xml, */*"
        },
        open_timeout: 10,
        read_timeout: 20
      )
      raise "HTTP fetch failed: #{result.error}" unless result.success?

      parse_feed(result.body)
    end

    def parse_feed(body)
      items = parse_rss_items(body)
      items = parse_atom_entries(body) if items.empty?
      return items if items.any?

      # No structured feed items — seed one low-confidence candidate from body preview.
      [
        {
          external_id: Digest::SHA256.hexdigest(body)[0, 24],
          title: @source.name,
          url: @source.endpoint_url,
          description: strip_html(body).truncate(500),
          content: body,
          raw: { "body_preview" => body.truncate(1000), "unstructured" => true },
          confidence: 0.25
        }
      ]
    end

    def parse_rss_items(body)
      items = []
      body.scan(%r{<item\b[^>]*>(.*?)</item>}mi).each_with_index do |(chunk), index|
        title = extract_tag(chunk, "title")
        link = extract_tag(chunk, "link").presence || extract_attr_link(chunk)
        description = extract_tag(chunk, "description").presence || extract_tag(chunk, "content:encoded")
        description = strip_html(description)
        published = extract_tag(chunk, "pubDate").presence || extract_tag(chunk, "dc:date")
        items << enrich_item(
          candidate_hash(
            title: title.presence || "Feed item #{index + 1}",
            link: link,
            description: description,
            content: chunk,
            confidence: 0.5,
            published_at: published,
            entity_type: default_entity_type
          )
        )
      end
      items
    end

    def parse_atom_entries(body)
      items = []
      body.scan(%r{<entry\b[^>]*>(.*?)</entry>}mi).each_with_index do |(chunk), index|
        title = extract_tag(chunk, "title")
        link = extract_atom_link(chunk)
        description = extract_tag(chunk, "summary").presence || extract_tag(chunk, "content")
        description = strip_html(description)
        published = extract_tag(chunk, "published").presence || extract_tag(chunk, "updated")
        items << enrich_item(
          candidate_hash(
            title: title.presence || "Atom entry #{index + 1}",
            link: link,
            description: description,
            content: chunk,
            confidence: 0.5,
            published_at: published,
            entity_type: default_entity_type
          )
        )
      end
      items
    end

    def enrich_item(item)
      return item if item[:url].blank?
      return item unless @source.config.is_a?(Hash) && @source.config["fetch_article_text"] == true

      article = Catalog::ArticleTextExtractor.call(url: item[:url])
      return item if article.blank?

      item.merge(
        content: "#{item[:content]}\n#{article}",
        raw: (item[:raw] || {}).merge("article_text" => article, "published_at" => item[:published_at])
      )
    end

    def candidate_hash(title:, link:, description:, content:, confidence:, published_at: nil, entity_type: nil)
      published = begin
        published_at.present? ? Time.zone.parse(published_at.to_s) : nil
      rescue ArgumentError, TypeError
        nil
      end

      {
        external_id: Digest::SHA256.hexdigest("#{link}-#{title}")[0, 24],
        title: title,
        url: link.presence,
        description: description,
        content: content,
        published_at: published,
        entity_type: entity_type || default_entity_type,
        raw: {
          "title" => title,
          "link" => link,
          "description" => description,
          "published_at" => published&.iso8601
        },
        confidence: confidence
      }
    end

    def extract_tag(chunk, tag)
      raw = chunk[%r{<#{Regexp.escape(tag)}\b[^>]*>(.*?)</#{Regexp.escape(tag)}>}mi, 1].to_s
      unwrap_cdata(raw).strip
    end

    def extract_attr_link(chunk)
      chunk[%r{<link[^>]*href=["']([^"']+)["']}i, 1].to_s.strip
    end

    def extract_atom_link(chunk)
      # Prefer rel=alternate, else first href
      alt = chunk[%r{<link[^>]*rel=["']alternate["'][^>]*href=["']([^"']+)["']}i, 1]
      alt.presence || chunk[%r{<link[^>]*href=["']([^"']+)["']}i, 1].to_s.strip
    end

    def unwrap_cdata(text)
      text.gsub(/\A<!\[CDATA\[(.*)\]\]>\z/m, '\1')
    end

    def strip_html(text)
      unwrap_cdata(text.to_s)
        .gsub(%r{<br\s*/?>}i, "\n")
        .gsub(%r{</p>}i, "\n")
        .gsub(/<[^>]+>/, " ")
        .gsub(/&nbsp;/, " ")
        .gsub(/&amp;/, "&")
        .gsub(/&lt;/, "<")
        .gsub(/&gt;/, ">")
        .gsub(/&quot;/, '"')
        .gsub(/\s+/, " ")
        .strip
    end

    def stub_items
      unless MocksAllowed.allowed?
        Rails.logger.warn("[Catalog] Skipping stub sync for source #{@source.id} — set endpoint_url or ALLOW_MOCKS=1")
        return []
      end

      stamp = Time.current.utc.strftime("%Y%m%d")
      [
        {
          external_id: "stub-#{@source.id}-#{stamp}",
          title: "#{@source.name} discovery #{stamp}",
          url: @source.endpoint_url,
          description: "Stub candidate from catalog sync for #{@source.name} (no endpoint_url configured)",
          content: "stub-#{@source.id}-#{stamp}",
          vendor: nil,
          entity_type: "tool",
          raw: { "stub" => true },
          confidence: 0.2
        }
      ]
    end
  end
end
