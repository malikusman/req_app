# frozen_string_literal: true

module Consultants
  class QuestionnaireProgress
    FIELD_IDS = %w[
      photo name email headline bio linkedin_url website location
      career_background seniority_level years_experience team_size_managed
      education_level field_of_study certifications
      industries_covered company_size_familiarity regional_expertise
      strengths review_focus
      ai_fluency_level ai_tools_familiarity
      review_capacity engagement_type preferred_company_types
      experiences
      cv_upload
    ].freeze

    SECTION_FIELDS = {
      1 => %w[photo name email headline bio linkedin_url website location],
      2 => %w[career_background seniority_level years_experience team_size_managed],
      3 => %w[education_level field_of_study certifications],
      4 => %w[industries_covered company_size_familiarity regional_expertise],
      5 => %w[strengths review_focus],
      6 => %w[ai_fluency_level ai_tools_familiarity],
      7 => %w[review_capacity engagement_type preferred_company_types],
      8 => %w[experiences],
      9 => %w[cv_upload]
    }.freeze

    def self.call(answers, consultant: nil)
      new(answers, consultant: consultant).call
    end

    def initialize(answers, consultant: nil)
      @answers = (answers || {}).to_h.stringify_keys
      @consultant = consultant
    end

    def call
      answerable = FIELD_IDS
      answered = answerable.count { |id| answered?(id) }
      percent = answerable.empty? ? 0 : ((answered.to_f / answerable.size) * 100).round
      {
        completion_percent: percent,
        answered_count: answered,
        answerable_count: answerable.size,
        section_status: SECTION_FIELDS.transform_values do |ids|
          touched = ids.any? { |id| answered?(id) }
          complete = ids.any? && ids.all? { |id| answered?(id) }
          { touched: touched, complete: complete }
        end
      }
    end

    private

    def answered?(id)
      case id
      when "photo"
        @consultant&.avatar_storage_key.present? || @answers["photo"].present?
      when "name"
        @consultant&.name.present? || @answers["name"].to_s.strip.present?
      when "email"
        @consultant&.email.present? || @answers["email"].to_s.strip.present?
      when "cv_upload"
        @consultant&.cv_storage_key.present? || @answers["cv_upload"].present?
      when "experiences"
        experiences_answered?
      else
        value = @answers[id]
        case value
        when nil then false
        when String then value.strip.present?
        when Array then value.any? { |v| v.is_a?(Hash) ? experience_row?(v) : v.to_s.strip.present? }
        else value.present?
        end
      end
    end

    def experiences_answered?
      rows = Array(@answers["experiences"])
      return rows.any? { |r| experience_row?(r) } if rows.any?

      @consultant&.consultant_experiences&.any? || false
    end

    def experience_row?(row)
      h = row.to_h.stringify_keys
      h["organization"].to_s.strip.present? && h["title"].to_s.strip.present?
    end
  end
end
