# frozen_string_literal: true

module Companies
  module ProfileContextSchema
    REQUIRED_SECTIONS = %w[basics strategy operations technology_data people_culture].freeze
    OPTIONAL_SECTIONS = %w[gaps_constraints documents_ack].freeze
    ALL_SECTIONS = (REQUIRED_SECTIONS + OPTIONAL_SECTIONS).freeze

    ONBOARDING_STEPS = (REQUIRED_SECTIONS + %w[documents review]).freeze
    TOTAL_ONBOARDING_STEPS = ONBOARDING_STEPS.size

    SECTION_REQUIRED_FIELDS = {
      "basics" => %w[industry company_size_band hq_country one_line_description],
      "strategy" => %w[top_priorities transformation_goals digital_vision_maturity success_metrics],
      "operations" => %w[primary_departments key_workflows systems_tools automation_level operational_pain_points],
      "technology_data" => %w[it_maturity integration_level data_governance security_posture],
      "people_culture" => %w[org_structure_notes change_readiness digital_literacy collaboration_tools]
    }.freeze

    OPTIONAL_SECTION_FIELDS = {
      "gaps_constraints" => %w[known_bottlenecks compliance_regulatory budget_timeline_constraints],
      "documents_ack" => %w[skipped_at]
    }.freeze

    DOCUMENT_CATEGORIES = %w[
      org_chart sop process_map policy financial other
    ].freeze

    def self.permitted_section?(section)
      ALL_SECTIONS.include?(section.to_s)
    end

    def self.sanitize_section_data(section, data)
      return {} unless data.is_a?(Hash)

      data = data.stringify_keys
      case section.to_s
      when "basics"
        data.slice(*SECTION_REQUIRED_FIELDS["basics"], "website")
      when "strategy"
        data.slice(*SECTION_REQUIRED_FIELDS["strategy"]).tap do |h|
          h["top_priorities"] = Array(h["top_priorities"]).map(&:to_s).reject(&:blank?).first(5)
        end
      when "operations"
        data.slice(*SECTION_REQUIRED_FIELDS["operations"]).tap do |h|
          h["primary_departments"] = Array(h["primary_departments"]).map(&:to_s).reject(&:blank?).first(10)
          h["systems_tools"] = Array(h["systems_tools"]).map(&:to_s).reject(&:blank?).first(15)
        end
      when "technology_data", "people_culture"
        data.slice(*SECTION_REQUIRED_FIELDS[section.to_s])
      when "gaps_constraints"
        data.slice(*OPTIONAL_SECTION_FIELDS["gaps_constraints"])
      when "documents_ack"
        data.slice("skipped_at")
      else
        {}
      end
    end
  end
end
