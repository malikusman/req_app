# frozen_string_literal: true

module Companies
  # Single source of truth for the v2 onboarding questionnaire: storage keys,
  # their step grouping and answer tier. Question text and option lists live
  # in the frontend config (Stage 2), not here.
  class QuestionnaireV2Config
    FIELDS = [
      # Step 1 of 8 — About Your Business
      { key: "q01_primary_industry", step: 1, tier: :essential },
      { key: "q02_business_description", step: 1, tier: :essential },
      { key: "q03_employee_count", step: 1, tier: :essential },
      { key: "q04_headquarters_country", step: 1, tier: :essential },
      { key: "q05_customer_types", step: 1, tier: :essential },
      { key: "q06_operating_sites", step: 1, tier: :essential },
      # Step 2 of 8 — Organisation & Business Processes
      { key: "q07_departments", step: 2, tier: :essential },
      { key: "q08_department_headcount", step: 2, tier: :recommended },
      { key: "q09_core_processes", step: 2, tier: :essential },
      { key: "q10_process_documentation", step: 2, tier: :essential },
      { key: "q10a_documentation_types", step: 2, tier: :conditional },
      { key: "q10b_certifications", step: 2, tier: :optional },
      { key: "q11_manual_process_areas", step: 2, tier: :essential },
      { key: "q12_department_handoffs", step: 2, tier: :optional },
      { key: "q13_key_person_dependency", step: 2, tier: :optional },
      { key: "q14_approval_methods", step: 2, tier: :essential },
      # Step 3 of 8 — How Work Gets Done
      { key: "q15_time_consuming_work", step: 3, tier: :essential },
      { key: "q16_information_types", step: 3, tier: :essential },
      { key: "q17_information_processing", step: 3, tier: :essential },
      { key: "q18_actions_after_review", step: 3, tier: :essential },
      { key: "q19_monitoring_activity", step: 3, tier: :essential },
      { key: "q20_content_research", step: 3, tier: :recommended },
      { key: "q21_high_volume_activity", step: 3, tier: :recommended },
      # Step 4 of 8 — Systems & Information
      { key: "q22_business_systems", step: 4, tier: :recommended },
      { key: "q23_productivity_tools", step: 4, tier: :essential },
      { key: "q24_system_connection", step: 4, tier: :essential },
      { key: "q25_manual_data_movement", step: 4, tier: :recommended },
      { key: "q25a_manual_movement_example", step: 4, tier: :optional },
      { key: "q26_information_storage", step: 4, tier: :essential },
      { key: "q27_information_findability", step: 4, tier: :essential },
      { key: "q28_reporting_method", step: 4, tier: :recommended },
      # Step 5 of 8 — External Business Activity
      { key: "q29_external_parties_channels", step: 5, tier: :essential },
      { key: "q30_external_manual_work", step: 5, tier: :essential },
      # Step 6 of 8 — Challenges & Priorities (Q33 displayed first; storage keeps spec numbering)
      { key: "q33_top_improvements", step: 6, tier: :essential },
      { key: "q31_operational_challenges", step: 6, tier: :essential },
      { key: "q32_error_delay_areas", step: 6, tier: :recommended },
      { key: "q34_active_projects", step: 6, tier: :optional },
      # Step 7 of 8 — AI, Automation & Employee Readiness
      { key: "q35_current_ai_automation", step: 7, tier: :essential },
      { key: "q36_adoption_readiness", step: 7, tier: :essential },
      { key: "q37_ai_employee_capability", step: 7, tier: :essential },
      { key: "q37a_ai_training", step: 7, tier: :recommended },
      { key: "q38_failed_ai_projects", step: 7, tier: :optional },
      # Step 8 of 8 — Governance & What You Want to Achieve
      { key: "q39_restrictions", step: 8, tier: :essential },
      { key: "q40_desired_outcomes", step: 8, tier: :essential },
      { key: "q41_specific_investigation", step: 8, tier: :optional }
    ].freeze

    FIELD_IDS = FIELDS.map { |field| field[:key] }.freeze
    STEP_FIELDS = FIELDS.group_by { |field| field[:step] }
                        .transform_values { |fields| fields.map { |field| field[:key] } }
                        .freeze
    TIERS = FIELDS.group_by { |field| field[:tier] }
                  .transform_values { |fields| fields.map { |field| field[:key] } }
                  .freeze
    TIERS_BY_KEY = FIELDS.to_h { |field| [field[:key], field[:tier]] }.freeze
    STEP_COUNT = STEP_FIELDS.size
  end
end