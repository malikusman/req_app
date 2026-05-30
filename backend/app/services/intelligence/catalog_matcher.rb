# frozen_string_literal: true

module Intelligence
  class CatalogMatcher
    def self.call(signal:)
      new(signal: signal).call
    end

    def self.match_opportunity(title:, description: nil, signal_type: nil)
      text = "#{title} #{description}".downcase
      departments = []
      signal_type = signal_type.to_s.presence

      SolutionCatalogEntry.active.select do |entry|
        tag_match = signal_type.present? && (entry.tags & [signal_type]).any?
        keyword_match = entry.match_keywords.any? { |kw| text.include?(kw.downcase) }
        desc_match = entry.description.to_s.downcase.split.any? { |word| word.length > 4 && text.include?(word) }
        tag_match || keyword_match || desc_match
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

    def initialize(signal:)
      @signal = signal
    end

    def call
      self.class.match_opportunity(
        title: @signal.label,
        description: @signal.signal_type,
        signal_type: @signal.signal_type
      )
    end
  end
end
