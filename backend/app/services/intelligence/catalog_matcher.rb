# frozen_string_literal: true

module Intelligence
  class CatalogMatcher
    def self.call(signal:)
      Catalog::HybridMatcher.call(
        query: signal.label.to_s,
        tags: [signal.signal_type, *Array(signal.departments)],
        keywords: signal.label.to_s.downcase.split(/\W+/).reject(&:blank?).first(6),
        limit: 2
      ).map do |match|
        {
          solution_id: match[:solution_catalog_entry_id] || match[:solution_id] || match[:id],
          name: match[:name],
          vendor: match[:vendor],
          url: match[:url] || match[:website_url],
          partnership_tier: match[:partnership_tier],
          category: match[:category],
          score: match[:score],
          reason: match[:reason],
          matched_at: Time.current.iso8601
        }
      end
    end
  end
end
