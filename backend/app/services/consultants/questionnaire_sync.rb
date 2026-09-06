# frozen_string_literal: true

module Consultants
  class QuestionnaireSync
    YEARS_MAP = {
      "<3 years" => 2,
      "3–7 years" => 5,
      "3-7 years" => 5,
      "8–15 years" => 11,
      "8-15 years" => 11,
      "16–25 years" => 20,
      "16-25 years" => 20,
      "25+ years" => 28
    }.freeze

    def self.call(consultant:, answers:)
      new(consultant: consultant, answers: answers).call
    end

    def initialize(consultant:, answers:)
      @consultant = consultant
      @answers = (answers || {}).to_h.stringify_keys
    end

    def call
      attrs = {}
      attrs[:headline] = @answers["headline"].to_s.strip.presence if @answers.key?("headline")
      attrs[:bio] = @answers["bio"].to_s.strip.presence if @answers.key?("bio")
      attrs[:linkedin_url] = @answers["linkedin_url"].to_s.strip.presence if @answers.key?("linkedin_url")
      attrs[:website_url] = website_value if @answers.key?("website") || @answers.key?("website_url")
      attrs[:location] = @answers["location"].to_s.strip.presence if @answers.key?("location")
      attrs[:years_experience] = mapped_years if @answers.key?("years_experience")
      attrs[:expertise_tags] = Array(@answers["strengths"]).map(&:to_s).map(&:strip).reject(&:blank?).uniq.first(12) if @answers.key?("strengths")
      attrs[:industries] = Array(@answers["industries_covered"]).map(&:to_s).map(&:strip).reject(&:blank?).uniq if @answers.key?("industries_covered")

      name = @answers["name"].to_s.strip.presence
      email = @answers["email"].to_s.strip.downcase.presence
      attrs[:name] = name if name
      attrs[:email] = email if email

      ActiveRecord::Base.transaction do
        @consultant.update!(attrs.compact) if attrs.compact.present?
        sync_experiences! if @answers.key?("experiences")
      end
      @consultant
    end

    private

    def website_value
      (@answers["website"] || @answers["website_url"]).to_s.strip.presence
    end

    def mapped_years
      raw = @answers["years_experience"]
      return raw.to_i if raw.is_a?(Numeric) || raw.to_s.match?(/\A\d+\z/)

      YEARS_MAP[raw.to_s] || raw.to_s[/\d+/]&.to_i
    end

    def sync_experiences!
      rows = Array(@answers["experiences"]).filter_map do |row|
        h = row.to_h.stringify_keys
        org = h["organization"].to_s.strip
        title = h["title"].to_s.strip
        next if org.blank? || title.blank?

        {
          organization: org,
          title: title,
          start_year: h["start_year"].presence&.to_i,
          end_year: h["end_year"].presence&.to_i,
          summary: h["summary"].to_s.strip.presence,
          sort_order: h["sort_order"].presence&.to_i
        }
      end

      @consultant.consultant_experiences.destroy_all
      rows.each_with_index do |attrs, index|
        @consultant.consultant_experiences.create!(
          organization: attrs[:organization],
          title: attrs[:title],
          start_year: attrs[:start_year],
          end_year: attrs[:end_year],
          summary: attrs[:summary],
          sort_order: attrs[:sort_order] || index
        )
      end
    end
  end
end
