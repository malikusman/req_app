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
              "fetched_at" => Time.current.iso8601
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
        errors: errors
      )
      @source.update!(last_sync_at: Time.current, last_sync_status: status)
      run
    rescue StandardError => e
      run&.update!(finished_at: Time.current, status: "failed", errors: [{ "error" => e.message }])
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
      response = Net::HTTP.get_response(uri)
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = response.body.to_s
      parse_feed(body)
    rescue StandardError => e
      Rails.logger.warn("[Catalog::SyncSourceService] fetch failed for source=#{@source.id}: #{e.message}")
      stub_items
    end

    def parse_feed(body)
      # Lightweight RSS-like stub: treat each <item> or newline-delimited JSON object.
      items = []
      body.scan(%r{<item>(.*?)</item>}m).each_with_index do |(chunk), index|
        title = chunk[%r{<title>(.*?)</title>}m, 1].to_s.strip
        link = chunk[%r{<link>(.*?)</link>}m, 1].to_s.strip
        description = chunk[%r{<description>(.*?)</description>}m, 1].to_s.strip
        items << {
          external_id: Digest::SHA256.hexdigest("#{link}-#{title}")[0, 24],
          title: title.presence || "Feed item #{index + 1}",
          url: link.presence,
          description: description,
          content: chunk,
          raw: { "title" => title, "link" => link, "description" => description },
          confidence: 0.45
        }
      end
      return items if items.any?

      # Fallback: hash entire body as one candidate seed
      [
        {
          external_id: Digest::SHA256.hexdigest(body)[0, 24],
          title: @source.name,
          url: @source.endpoint_url,
          description: body.truncate(500),
          content: body,
          raw: { "body_preview" => body.truncate(1000) },
          confidence: 0.3
        }
      ]
    end

    def stub_items
      stamp = Time.current.utc.strftime("%Y%m%d")
      [
        {
          external_id: "stub-#{@source.id}-#{stamp}",
          title: "#{@source.name} discovery #{stamp}",
          url: @source.endpoint_url,
          description: "Stub candidate from catalog sync for #{@source.name}",
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
