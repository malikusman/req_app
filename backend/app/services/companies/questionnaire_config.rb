# frozen_string_literal: true

module Companies
  # The company onboarding questionnaire: storage keys, step grouping and answer
  # tier. Question text and option lists live in the frontend config
  # (frontend/src/lib/questionnaireOptions.ts); this is the authority on what may
  # be stored, where it sits, and whether it counts toward completion.
  #
  # There is one questionnaire. An earlier rebuild carried a `questionnaire_version`
  # column so v1 and v2 could run side by side; with no live data to migrate that
  # was pure cost, so the new set simply replaced the old one. Nothing reads a
  # version, and old v1 keys are not in the whitelist — any that linger in a
  # company's answers blob are inert.
  class QuestionnaireConfig
    # tier semantics:
    #   essential   — counts toward the completion percent; nothing else does
    #   recommended — encouraged, never pressed
    #   optional    — freely skipped
    #   conditional — only shown when another answer calls for it (see :show_when)
    #
    # Only Essential counts, deliberately: a percentage that never reaches 100
    # unless someone answers every optional question reads as nagging, and the
    # client asked for the opposite.
    FIELDS = [
      # Step 1 — About your business
      { key: "q01_primary_industry", step: 1, tier: :essential, with_other: true },
      { key: "q02_business_description", step: 1, tier: :essential },
      { key: "q03_employee_count", step: 1, tier: :essential },
      { key: "q04_headquarters_country", step: 1, tier: :essential },
      { key: "q05_customer_types", step: 1, tier: :essential, with_other: true },
      { key: "q06_operating_sites", step: 1, tier: :essential },
      # Step 2 — Organisation & business processes
      { key: "q07_departments", step: 2, tier: :essential, with_other: true },
      # Storage is a hash of department => headcount string, keyed by whatever Q07
      # selected. "Not sure" is a legitimate value, not a blank.
      { key: "q08_department_headcount", step: 2, tier: :recommended, shape: :hash },
      { key: "q09_core_processes", step: 2, tier: :essential, with_other: true },
      { key: "q10_process_documentation", step: 2, tier: :essential },
      { key: "q10a_documentation_types", step: 2, tier: :conditional, with_other: true,
        show_when: { field: "q10_process_documentation",
                     not_one_of: ["We do not have formal process documentation", "Not sure"] } },
      # Two "Other" options in the copy ("Other ISO certification", "Other formal
      # certification") share one sidecar — the decision, made once, is not to try
      # to distinguish which was meant.
      { key: "q10b_certifications", step: 2, tier: :optional, with_other: true },
      { key: "q11_manual_process_areas", step: 2, tier: :essential, with_other: true },
      { key: "q12_department_handoffs", step: 2, tier: :optional },
      { key: "q13_key_person_dependency", step: 2, tier: :optional },
      { key: "q14_approval_methods", step: 2, tier: :essential },
      # Step 3 — How work gets done
      { key: "q15_time_consuming_work", step: 3, tier: :essential, with_other: true },
      # Selections stay a plain array; the rough volume per selection rides in the
      # companion `_detail` hash, so everything that already reads multi-selects as
      # string arrays keeps working.
      { key: "q21_high_volume_activity", step: 3, tier: :recommended, with_other: true, with_detail: true },
      { key: "q16_information_types", step: 3, tier: :essential, with_other: true },
      { key: "q17_information_processing", step: 3, tier: :essential, with_other: true },
      { key: "q18_actions_after_review", step: 3, tier: :essential, with_other: true },
      { key: "q19_monitoring_activity", step: 3, tier: :essential, with_other: true },
      { key: "q20_content_research", step: 3, tier: :recommended, with_other: true },
      # Step 4 — Systems & information
      { key: "q22_business_systems", step: 4, tier: :recommended, shape: :hash },
      { key: "q23_productivity_tools", step: 4, tier: :essential, with_other: true },
      { key: "q24_system_connection", step: 4, tier: :essential },
      { key: "q25_manual_data_movement", step: 4, tier: :recommended, with_other: true },
      { key: "q25a_manual_movement_example", step: 4, tier: :optional },
      { key: "q26_information_storage", step: 4, tier: :essential, with_other: true },
      { key: "q27_information_findability", step: 4, tier: :essential },
      { key: "q28_reporting_method", step: 4, tier: :recommended, with_other: true },
      # Step 5 — External business activity
      # Genuinely two-stage: a hash of party => channels used with that party.
      { key: "q29_external_parties_channels", step: 5, tier: :essential, with_other: true, shape: :hash },
      { key: "q30_external_manual_work", step: 5, tier: :essential, with_other: true },
      # Step 6 — Challenges & priorities (Q33 is asked first; keys keep spec numbering)
      # Three ranked answers in order, so storage is a fixed-length array.
      { key: "q33_top_improvements", step: 6, tier: :essential, shape: :array },
      { key: "q31_operational_challenges", step: 6, tier: :essential, with_other: true },
      { key: "q32_error_delay_areas", step: 6, tier: :recommended, with_other: true },
      { key: "q34_active_projects", step: 6, tier: :optional },
      # Step 7 — AI, automation & employee readiness
      { key: "q35_current_ai_automation", step: 7, tier: :essential, with_other: true },
      # Q36 (self-rated adoption readiness) and Q37 (self-rated employee AI
      # capability) were removed deliberately. A company's own estimate of its
      # readiness is the least reliable thing it can tell us — people either
      # flatter themselves or undersell, and both corrupt the analysis. Readiness
      # is read off the work itself in discovery. Q37a stays because it asks what
      # training actually exists, which is a fact; it keeps its key rather than
      # being renumbered, since keys address stored data, not screen position.
      { key: "q37a_ai_training", step: 7, tier: :recommended },
      { key: "q38_failed_ai_projects", step: 7, tier: :optional },
      # Step 8 — Governance & what you want to achieve
      { key: "q39_restrictions", step: 8, tier: :essential, with_other: true },
      { key: "q40_desired_outcomes", step: 8, tier: :essential, with_other: true },
      { key: "q41_specific_investigation", step: 8, tier: :optional }
    ].freeze

    FIELD_IDS = FIELDS.map { |f| f[:key] }.freeze
    BY_KEY = FIELDS.to_h { |f| [f[:key], f] }.freeze
    STEP_FIELDS = FIELDS.group_by { |f| f[:step] }
                        .transform_values { |fs| fs.map { |f| f[:key] } }
                        .freeze
    STEP_COUNT = STEP_FIELDS.size
    TIERS_BY_KEY = FIELDS.to_h { |f| [f[:key], f[:tier]] }.freeze
    ESSENTIAL_KEYS = FIELDS.select { |f| f[:tier] == :essential }.map { |f| f[:key] }.freeze
    CONDITIONAL = FIELDS.select { |f| f[:show_when] }.to_h { |f| [f[:key], f[:show_when]] }.freeze

    # Companion keys. They are never questionnaire fields in their own right, so
    # they never appear in FIELD_IDS and never count toward completion — but they
    # must be storable, which is what WHITELIST is for.
    SIDECAR_KEYS = FIELDS.filter_map { |f| "#{f[:key]}_other" if f[:with_other] }.freeze
    DETAIL_KEYS = FIELDS.filter_map { |f| "#{f[:key]}_detail" if f[:with_detail] }.freeze
    WHITELIST = (FIELD_IDS + SIDECAR_KEYS + DETAIL_KEYS).freeze

    OTHER_TEXT_MAX_LENGTH = 120

    # Whether a conditional field is currently in play. A hidden field must not be
    # counted as missing, or the percent can never reach 100.
    def self.visible?(key, answers)
      rule = CONDITIONAL[key]
      return true unless rule

      value = answers[rule[:field]]
      value = value.first if value.is_a?(Array)
      return false if value.blank?

      rule[:not_one_of].exclude?(value.to_s)
    end
  end
end
