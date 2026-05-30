# frozen_string_literal: true

module Companies
  class ProfileSummary
    def self.for_display(company:)
      new(company: company).for_display
    end

    def self.for_ai(company:)
      new(company: company).for_ai
    end

    def initialize(company:)
      @company = company
      @context = (company.profile_context || {}).deep_stringify_keys
    end

    def for_display
      sections = ProfileContextSchema::REQUIRED_SECTIONS.filter_map do |section|
        data = @context[section]
        next if data.blank?

        { section: section, label: section_label(section), fields: humanize_section(data) }
      end

      optional = %w[gaps_constraints].filter_map do |section|
        data = @context[section]
        next if data.blank?

        { section: section, label: section_label(section), fields: humanize_section(data) }
      end

      {
        company_name: @company.display_name || @company.name,
        sections: sections + optional
      }
    end

    def for_ai
      lines = ["Company: #{@company.display_name || @company.name}"]
      ProfileContextSchema::REQUIRED_SECTIONS.each do |section|
        data = @context[section]
        next if data.blank?

        lines << "#{section_label(section)}:"
        humanize_section(data).each { |k, v| lines << "  #{k}: #{v}" }
      end

      gaps = @context["gaps_constraints"]
      if gaps.present?
        lines << "Gaps and constraints:"
        humanize_section(gaps).each { |k, v| lines << "  #{k}: #{v}" }
      end

      lines.join("\n")
    end

    private

    def section_label(section)
      {
        "basics" => "Company basics",
        "strategy" => "Strategy and goals",
        "operations" => "Operations and systems",
        "technology_data" => "Technology and data",
        "people_culture" => "People and culture",
        "gaps_constraints" => "Gaps and constraints"
      }[section] || section.humanize
    end

    def humanize_section(data)
      data.each_with_object({}) do |(key, value), acc|
        label = key.humanize
        acc[label] = format_value(value)
      end
    end

    def format_value(value)
      case value
      when Array then value.join(", ")
      else value.to_s
      end
    end
  end
end
