# frozen_string_literal: true

module Pricing
  # What the Stage 1 fee is calculated from (Doc 17 §2.2), read from the
  # engagement and the company's confirmed facts — never from anything anyone
  # said in a conversation (Doc 05 §4.3, Doc 17 §15).
  #
  # An administrator may correct three of them before approving (Doc 17 §9.2,
  # "adjust"): the number of deep dives, which defaults to the number of
  # participants kept within the rate card's range (Decision Register D9: 3–5);
  # the number of locations, which comes from free text in the company profile;
  # and the country whose tax applies. Each value records where it came from.
  class Stage1Inputs
    ADJUSTABLE = %w[deep_dives locations country].freeze

    # The country is free text at onboarding (O3); the tax rate is looked up by
    # ISO code.
    COUNTRY_CODES = {
      "AE" => ["ae", "uae", "u.a.e.", "united arab emirates", "emirates", "dubai", "abu dhabi", "sharjah"],
      "SA" => ["sa", "ksa", "saudi arabia", "kingdom of saudi arabia", "saudi"],
      "QA" => %w[qa qatar],
      "BH" => %w[bh bahrain],
      "KW" => %w[kw kuwait],
      "OM" => %w[om oman],
      "GB" => ["gb", "uk", "united kingdom"],
      "PK" => %w[pk pakistan]
    }.freeze

    attr_reader :participants, :departments, :key_persons, :named_participants, :languages, :locations, :country,
                :deep_dives, :industry, :size_band, :sources

    def self.from(engagement, adjustments = {})
      profile = engagement.company.company_profile || {}
      adjustments = adjustments.to_h.stringify_keys.slice(*ADJUSTABLE).compact_blank

      new(
        participants: engagement.planned_participant_count,
        departments: Array(engagement.planned_departments).map { |row| { "name" => row["name"], "count" => row["count"] } },
        key_persons: engagement.participants.key_persons.where.not(participation_status: "DECLINED").count,
        named_participants: engagement.participants.employees.count,
        languages: Array(engagement.languages).presence || ["en"],
        locations: adjustments.key?("locations") ? adjustments["locations"].to_i : profile_locations(profile),
        country: adjustments.key?("country") ? country_code(adjustments["country"]) : country_code(profile["country"]),
        deep_dives: adjustments["deep_dives"]&.to_i,
        industry: profile["industry"], size_band: profile["size_band"],
        sources: ADJUSTABLE.index_with { |key| adjustments.key?(key) ? "ADMINISTRATOR" : "ENGAGEMENT" }
      )
    end

    # Rebuilds the inputs a quote was made from, with an administrator's
    # corrections on top.
    def self.from_h(hash, adjustments = {})
      hash = hash.to_h.stringify_keys
      adjustments = adjustments.to_h.stringify_keys.slice(*ADJUSTABLE).compact_blank
      merged = hash.merge(adjustments.transform_values { |v| v.is_a?(String) && v.match?(/\A\d+\z/) ? v.to_i : v })
      merged["country"] = country_code(merged["country"]) if adjustments.key?("country")
      sources = hash.fetch("sources", {}).merge(adjustments.keys.index_with { "ADMINISTRATOR" })

      new(**merged.slice(*%w[participants departments key_persons named_participants languages locations country
                             deep_dives industry size_band]).symbolize_keys, sources: sources)
    end

    def self.profile_locations(profile)
      list = profile["locations"]
      list.is_a?(Array) ? [list.reject(&:blank?).size, 1].max : 1
    end

    def self.country_code(value)
      return nil if value.blank? || value == Companies::ProfileUpdater::UNKNOWN || Companies::OnboardingFields.not_sure?(value)

      text = value.to_s.strip.downcase

      COUNTRY_CODES.find { |_code, names| names.include?(text) }&.first || (text.match?(/\A[a-z]{2}\z/) ? text.upcase : value.to_s.strip)
    end

    # rubocop:disable Metrics/ParameterLists
    def initialize(participants:, departments:, key_persons:, named_participants:, languages:, locations:, country:,
                   deep_dives:, industry: nil, size_band: nil, sources: {})
      @participants = participants
      @departments = departments
      @key_persons = key_persons.to_i
      @named_participants = named_participants.to_i
      @languages = Array(languages)
      @locations = [locations.to_i, 1].max
      @country = country
      @deep_dives = deep_dives
      @industry = industry
      @size_band = size_band
      @sources = sources
    end
    # rubocop:enable Metrics/ParameterLists

    def to_h
      { "participants" => participants, "departments" => departments, "key_persons" => key_persons,
        "named_participants" => named_participants, "languages" => languages, "locations" => locations,
        "country" => country, "deep_dives" => deep_dives, "industry" => industry, "size_band" => size_band,
        "sources" => sources }
    end
  end
end
