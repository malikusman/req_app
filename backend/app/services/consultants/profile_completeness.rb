# frozen_string_literal: true

module Consultants
  class ProfileCompleteness
    REQUIRED_CHECKS = %i[headline bio linkedin_url expertise_tags experiences].freeze

    Result = Struct.new(:percent, :complete, :missing, :checks, keyword_init: true)

    def self.call(consultant)
      new(consultant).call
    end

    def initialize(consultant)
      @consultant = consultant
    end

    def call
      checks = {
        headline: @consultant.headline.present?,
        bio: @consultant.bio.to_s.length >= 80,
        linkedin_url: @consultant.linkedin_url.present?,
        expertise_tags: @consultant.expertise_tags.size >= 3,
        experiences: @consultant.consultant_experiences.any?
      }
      met = checks.count { |_, v| v }
      total = checks.size
      missing = checks.filter_map { |key, ok| key unless ok }.map(&:to_s)
      percent = ((met.to_f / total) * 100).round
      complete = REQUIRED_CHECKS.all? { |k| checks[k] }

      Result.new(percent: percent, complete: complete, missing: missing, checks: checks)
    end
  end
end
