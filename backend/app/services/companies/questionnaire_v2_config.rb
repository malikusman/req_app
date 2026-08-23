# frozen_string_literal: true

module Companies
  # Single source of truth for the v2 onboarding questionnaire: storage keys,
  # their step grouping and answer tier. Question text and option lists live
  # in the frontend config (Stage 2), not here.
  class QuestionnaireV2Config
    FIELDS = [
      # Step 1 of 8 — About Your Business
      { key: "q01_primary_industry", step: 1, tier: :essential, with_other: true },
      { key: "q02_business_description", step: 1, tier: :essential },
      { key: "q03_employee_count", step: 1, tier: :essential },
      { key: "q04_headquarters_country", step: 1, tier: :essential },
      { key: "q05_customer_types", step: 1, tier: :essential, with_other: true },
      { key: "q06_operating_sites", step: 1, tier: :essential },
      # Step 2 of 8 — Organisation & Business Processes
      { key: "q07_departments", step: 2, tier: :essential, with_other: true },
      { key: "q08_department_headcount", step: 2, tier: :recommended },
      { key: "q09_core_processes", step: 2, tier: :essential, with_other: true },
      { key: "q10_process_documentation", step: 2, tier: :essential },
      { key: "q10a_documentation_types", step: 2, tier: :conditional, with_other: true },
      # q10b has two "Other" options in the frontend copy ("Other ISO certification",
      # "Other formal certification / standard") but a single shared sidecar key —
      # the decision, made once, is not to try to distinguish which was meant.
      { key: "q10b_certifications", step: 2, tier: :optional, with_other: true },
      { key: "q11_manual_process_areas", step: 2, tier: :essential, with_other: true },
      { key: "q12_department_handoffs", step: 2, tier: :optional },
      { key: "q13_key_person_dependency", step: 2, tier: :optional },
      { key: "q14_approval_methods", step: 2, tier: :essential },
      # Step 3 of 8 — How Work Gets Done
      { key: "q15_time_consuming_work", step: 3, tier: :essential, with_other: true },
      { key: "q16_information_types", step: 3, tier: :essential, with_other: true },
      { key: "q17_information_processing", step: 3, tier: :essential, with_other: true },
      { key: "q18_actions_after_review", step: 3, tier: :essential, with_other: true },
      { key: "q19_monitoring_activity", step: 3, tier: :essential, with_other: true },
      { key: "q20_content_research", step: 3, tier: :recommended, with_other: true },
      { key: "q21_high_volume_activity", step: 3, tier: :recommended, with_other: true },
      # Step 4 of 8 — Systems & Information
      { key: "q22_business_systems", step: 4, tier: :recommended },
      { key: "q23_productivity_tools", step: 4, tier: :essential, with_other: true },
      { key: "q24_system_connection", step: 4, tier: :essential },
      { key: "q25_manual_data_movement", step: 4, tier: :recommended, with_other: true },
      { key: "q25a_manual_movement_example", step: 4, tier: :optional },
      { key: "q26_information_storage", step: 4, tier: :essential, with_other: true },
      { key: "q27_information_findability", step: 4, tier: :essential },
      { key: "q28_reporting_method", step: 4, tier: :recommended, with_other: true },
      # Step 5 of 8 — External Business Activity
      # q29 has two "Other" entries (Parties group, Channels group) but is being
      # rebuilt as a two_stage_matrix in a later session — deliberately not given
      # with_other here; wire it up alongside that rebuild instead.
      { key: "q29_external_parties_channels", step: 5, tier: :essential },
      { key: "q30_external_manual_work", step: 5, tier: :essential, with_other: true },
      # Step 6 of 8 — Challenges & Priorities (Q33 displayed first; storage keeps spec numbering)
      { key: "q33_top_improvements", step: 6, tier: :essential },
      { key: "q31_operational_challenges", step: 6, tier: :essential, with_other: true },
      { key: "q32_error_delay_areas", step: 6, tier: :recommended, with_other: true },
      { key: "q34_active_projects", step: 6, tier: :optional },
      # Step 7 of 8 — AI, Automation & Employee Readiness
      { key: "q35_current_ai_automation", step: 7, tier: :essential, with_other: true },
      { key: "q36_adoption_readiness", step: 7, tier: :essential },
      { key: "q37_ai_employee_capability", step: 7, tier: :essential },
      { key: "q37a_ai_training", step: 7, tier: :recommended },
      { key: "q38_failed_ai_projects", step: 7, tier: :optional },
      # Step 8 of 8 — Governance & What You Want to Achieve
      { key: "q39_restrictions", step: 8, tier: :essential, with_other: true },
      { key: "q40_desired_outcomes", step: 8, tier: :essential, with_other: true },
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

    # Sidecar free-text keys for fields with with_other: true (e.g. "q01_primary_industry_other").
    # These are never added to FIELDS, so they never appear in FIELD_IDS/TIERS/STEP_FIELDS —
    # they must not count toward completion or be treated as a questionnaire field.
    SIDECAR_KEYS = FIELDS.filter_map { |f| "#{f[:key]}_other" if f[:with_other] }.freeze
    WHITELIST = (FIELD_IDS + SIDECAR_KEYS).freeze
    OTHER_TEXT_MAX_LENGTH = 120
  end
end