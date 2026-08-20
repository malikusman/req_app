# frozen_string_literal: true

module Companies
  # Computes questionnaire completion percent and section touch state.
  class QuestionnaireProgress
    FIELD_IDS = %w[
      company_industry company_size company_location business_model annual_revenue
      departments_present operational_structure num_locations department_pain_point
      erp_system crm_system accounting_software hr_software communication_tools tech_stack_maturity
      manual_processes repetitive_task_frequency approval_workflow reporting_frequency
      data_storage_location document_types document_volume search_difficulty
      customer_channels monthly_inquiry_volume response_time_current support_team_size
      top_bottlenecks time_lost_estimate error_prone_areas
      current_ai_usage ai_tools_used desired_ai_functions ai_openness
      data_hosting compliance_requirements security_posture
      primary_goals timeline budget_range additional_context
    ].freeze

    SECTION_FIELDS = {
      1 => %w[company_industry company_size company_location business_model annual_revenue],
      2 => %w[departments_present operational_structure num_locations department_pain_point],
      3 => %w[erp_system crm_system accounting_software hr_software communication_tools tech_stack_maturity],
      4 => %w[manual_processes repetitive_task_frequency approval_workflow reporting_frequency],
      5 => %w[data_storage_location document_types document_volume search_difficulty],
      6 => %w[customer_channels monthly_inquiry_volume response_time_current support_team_size],
      7 => %w[top_bottlenecks time_lost_estimate error_prone_areas],
      8 => %w[current_ai_usage ai_tools_used desired_ai_functions ai_openness],
      9 => %w[data_hosting compliance_requirements security_posture],
      10 => %w[primary_goals timeline budget_range additional_context]
    }.freeze

    def self.call(answers)
      new(answers).call
    end

    # Version-aware entry used by controllers and summary services. v2 companies
    # compute against QuestionnaireV2Config; v1 companies keep the historical
    # behaviour exactly. `call` itself stays unchanged (the v1 path).
    def self.call_for_company(company, answers: nil)
      payload = answers || company.questionnaire_answers
      return QuestionnaireV2Progress.call(payload) if company.questionnaire_version.to_i >= 2

      call(payload)
    end

    def initialize(answers)
      @answers = (answers || {}).to_h.stringify_keys
    end

    def call
      answerable = answerable_fields
      answered = answerable.count { |id| answered?(id) }
      percent = answerable.empty? ? 0 : ((answered.to_f / answerable.size) * 100).round
      {
        completion_percent: percent,
        answered_count: answered,
        answerable_count: answerable.size,
        section_status: SECTION_FIELDS.transform_values do |ids|
          visible = ids.select { |id| answerable.include?(id) }
          touched = visible.any? { |id| answered?(id) }
          complete = visible.any? && visible.all? { |id| answered?(id) }
          { touched: touched, complete: complete }
        end
      }
    end

    private

    def answerable_fields
      fields = FIELD_IDS.dup
      usage = @answers["current_ai_usage"].to_s
      if usage.blank? || usage == "No, not yet"
        fields -= ["ai_tools_used"]
      end
      fields
    end

    def answered?(id)
      value = @answers[id]
      case value
      when nil then false
      when String then value.strip.present?
      when Array then value.any? { |v| v.to_s.strip.present? }
      else value.present?
      end
    end
  end
end
