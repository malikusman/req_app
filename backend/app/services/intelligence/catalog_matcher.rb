# frozen_string_literal: true

module Intelligence
  class CatalogMatcher
    def self.call(signal:)
      new(signal: signal).call
    end

    def initialize(signal:)
      @signal = signal
    end

    def call
      SolutionCatalogEntry.active.select do |entry|
        tag_match = (entry.tags & [@signal.signal_type, *@signal.departments]).any?
        keyword_match = entry.match_keywords.any? { |kw| @signal.label.downcase.include?(kw.downcase) }
        tag_match || keyword_match
      end.first(2).map do |entry|
        {
          solution_id: entry.id,
          name: entry.name,
          vendor: entry.vendor,
          url: entry.website_url,
          partnership_tier: entry.partnership_tier,
          category: entry.category
        }
      end
    end
  end
end
