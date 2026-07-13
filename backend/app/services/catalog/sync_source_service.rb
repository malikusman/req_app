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

          CatalogCandidate.create!(
            catalog_source_record: record,
            name: item[:title].presence || "Untitled candidate",
            vendor: item[:vendor],
            entity_type: item[:entity_type].presence || "tool",
            description: item[:description],
            website_url: item[:url],
            confidence: item[:confidence] || 0.4,
            review_status: "pending",
            provenance: {
              "catalog_source_id" => @source.id,
              "catalog_sync_run_id" => run.id,
              "fingerprint" => fingerprint,
              "fetched_at" => Time.current.iso8601,
              "stub" => item[:raw].is_a?(Hash) && item[:raw]["stub"] == true
            }
          )
          created += 1
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
      if @source.endpoint_url.present?
        fetch_from_endpoint
      else
        stub_items
      end
    end

    def fetch_from_endpoint
      uri = URI(@source.endpoint_url)
      raise "Unsupported URL scheme" unless uri.is_a?(URI::HTTP)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "ReqCatalogSync/1.0"
        req["Accept"] = "application/rss+xml, application/atom+xml, application/xml, text/xml, */*"
        http.request(req)
      end
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      parse_feed(response.body.to_s)
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
        items << candidate_hash(
          title: title.presence || "Feed item #{index + 1}",
          link: link,
          description: description,
          content: chunk,
          confidence: 0.5
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
        items << candidate_hash(
          title: title.presence || "Atom entry #{index + 1}",
          link: link,
          description: description,
          content: chunk,
          confidence: 0.5
        )
      end
      items
    end

    def candidate_hash(title:, link:, description:, content:, confidence:)
      {
        external_id: Digest::SHA256.hexdigest("#{link}-#{title}")[0, 24],
        title: title,
        url: link.presence,
        description: description,
        content: content,
        raw: { "title" => title, "link" => link, "description" => description },
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
