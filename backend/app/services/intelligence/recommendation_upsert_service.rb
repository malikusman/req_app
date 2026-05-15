# frozen_string_literal: true

module Intelligence
  class RecommendationUpsertService
    def self.call(company:, recommendations:)
      new(company: company, recommendations: recommendations).call
    end

    def initialize(company:, recommendations:)
      @company = company
      @recommendations = recommendations
    end

    def call
      @recommendations.each do |attrs|
        rec = Recommendation.find_or_initialize_by(company: @company, title: attrs[:title])
        rec.assign_attributes(
          description: attrs[:description],
          implementation_outline: attrs[:implementation_outline],
          priority: attrs[:priority],
          status: "published",
          catalog_matches: attrs[:catalog_matches],
          related_signal_ids: attrs[:related_signal_ids],
          related_pattern_ids: attrs[:related_pattern_ids]
        )
        rec.save!
      end
    end
  end
end
