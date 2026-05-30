# frozen_string_literal: true

module Companies
  class ProfileCompleteness
    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
      @context = (company.profile_context || {}).deep_stringify_keys
    end

    def call
      {
        required_sections_complete: required_sections_complete?,
        completeness_percent: completeness_percent,
        missing_required_sections: missing_required_sections,
        section_status: section_status
      }
    end

    def required_sections_complete?
      missing_required_sections.empty?
    end

    def completeness_percent
      total = ProfileContextSchema::REQUIRED_SECTIONS.sum do |section|
        ProfileContextSchema::SECTION_REQUIRED_FIELDS[section].size
      end
      return 100 if total.zero?

      filled = ProfileContextSchema::REQUIRED_SECTIONS.sum do |section|
        ProfileContextSchema::SECTION_REQUIRED_FIELDS[section].count { |field| field_present?(section, field) }
      end
      ((filled.to_f / total) * 100).round
    end

    def missing_required_sections
      ProfileContextSchema::REQUIRED_SECTIONS.reject { |section| section_complete?(section) }
    end

    def section_complete?(section)
      ProfileContextSchema::SECTION_REQUIRED_FIELDS[section].all? { |field| field_present?(section, field) }
    end

    def current_onboarding_step
      return ProfileContextSchema::TOTAL_ONBOARDING_STEPS + 1 if @company.portal_onboarding_completed_at.present?

      ProfileContextSchema::REQUIRED_SECTIONS.each_with_index do |section, idx|
        return idx + 1 unless section_complete?(section)
      end

      return 7 if documents_ack_complete?

      6
    end

    private

    def section_status
      ProfileContextSchema::ALL_SECTIONS.index_with do |section|
        if ProfileContextSchema::REQUIRED_SECTIONS.include?(section)
          section_complete?(section) ? "complete" : "incomplete"
        elsif section == "documents_ack"
          documents_ack_complete? ? "complete" : "optional"
        else
          optional_section_complete?(section) ? "complete" : "optional"
        end
      end
    end

    def documents_ack_complete?
      @context.dig("documents_ack", "skipped_at").present? ||
        @company.documents.where(source: "company_portal_upload").exists?
    end

    def optional_section_complete?(section)
      fields = ProfileContextSchema::OPTIONAL_SECTION_FIELDS[section] || []
      section_data = @context[section] || {}
      fields.any? { |field| value_present?(section_data[field]) }
    end

    def field_present?(section, field)
      section_data = @context[section] || {}
      value_present?(section_data[field])
    end

    def value_present?(value)
      case value
      when Array then value.any? { |v| v.to_s.strip.present? }
      when String then value.strip.present?
      else value.present?
      end
    end
  end
end
