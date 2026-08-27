# frozen_string_literal: true

module Catalog
  class PromoteCandidateService
    def self.call(candidate:, platform_user:, review_note: nil, attributes: {})
      new(candidate: candidate, platform_user: platform_user, review_note: review_note, attributes: attributes).call
    end

    def initialize(candidate:, platform_user:, review_note: nil, attributes: {})
      @candidate = candidate
      @platform_user = platform_user
      @review_note = review_note
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      raise ArgumentError, "Candidate already reviewed" unless @candidate.review_status == "pending"

      entry = nil
      ActiveRecord::Base.transaction do
        entry = SolutionCatalogEntry.create!(
          name: @attributes[:name].presence || @candidate.name,
          vendor: @attributes[:vendor].presence || @candidate.vendor,
          category: @attributes[:category].presence || map_category(@candidate.entity_type),
          description: @attributes[:description].presence || @candidate.description,
          website_url: @attributes[:website_url].presence || @candidate.website_url,
          tags: Array(@attributes[:tags]),
          match_keywords: Array(@attributes[:match_keywords]),
          active: true,
          partnership_tier: @attributes[:partnership_tier].presence || "none",
          entity_type: @attributes[:entity_type].presence || @candidate.entity_type,
          published_at: Time.current,
          owned_by_platform_user_id: @platform_user.id,
          metadata: {
            "promoted_from_candidate_id" => @candidate.id,
            "provenance" => @candidate.provenance
          }
        )

        @candidate.update!(
          review_status: "approved",
          suggested_catalog_entry: entry,
          reviewed_by_platform_user: @platform_user,
          reviewed_at: Time.current,
          review_note: @review_note
        )
      end

      # Rematch so promoted tools reach company catalog (and consultants) without waiting
      # for the next full intelligence aggregate.
      RematchCompanyCatalogJob.perform_later

      entry
    end

    private

    def map_category(entity_type)
      case entity_type
      when "agent" then "ai_agent"
      when "integration" then "integration"
      when "service", "app", "model" then "saas"
      else "automation"
      end
    end
  end
end
