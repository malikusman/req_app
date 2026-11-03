# frozen_string_literal: true

module Companies
  # One-off move of what the old onboarding stored that the profile may no longer
  # hold (Doc 07 §13): management's goals and the revenue band go to legacy_profile,
  # where only consultants see them, and document-analysis output built from the old
  # questionnaire is retired so employee interviews stop reading it.
  #
  # Safe to run twice: everything it moves is gone from the source after the first
  # run, and nothing already in legacy_profile is overwritten.
  class LegacyProfileMigration
    MOVED_KEYS = %w[business_goals annual_revenue_band].freeze

    def self.call(company)
      new(company).call
    end

    def initialize(company)
      @company = company
    end

    def call
      profile = (@company.company_profile || {}).to_h.stringify_keys
      legacy = (@company.legacy_profile || {}).to_h.stringify_keys
      answers = (@company.questionnaire_answers || {}).to_h

      MOVED_KEYS.each do |key|
        next unless profile.key?(key)

        value = profile.delete(key)
        legacy[key] = value if value.present? && !legacy.key?(key)
      end
      remap_size!(profile, legacy, answers)

      @company.update_columns(
        company_profile: profile,
        legacy_profile: legacy,
        profile_provenance: provenance_for(profile, answers)
      )
      retire_questionnaire_informed_analysis!
      @company
    end

    private

    # The old bands 201-1000 and 500+ don't fit Company::SIZE_BANDS. The original
    # questionnaire answer, when there is one, says exactly which band; otherwise
    # the old value is kept for the consultant and the size is left unknown rather
    # than guessed.
    def remap_size!(profile, legacy, answers)
      size = profile["size_band"]
      return if size.blank? || ::Company::SIZE_BANDS.include?(size)

      mapped = QuestionnaireSync::SIZE_MAP[answers["q03_employee_count"].to_s]
      if mapped
        profile["size_band"] = mapped
      else
        legacy["size_band_v1"] ||= size
        profile.delete("size_band")
      end
    end

    def provenance_for(profile, answers)
      provenance = (@company.profile_provenance || {}).to_h.stringify_keys
      source = answers.present? ? "LEGACY_QUESTIONNAIRE" : "USER_ENTERED"
      at = (@company.questionnaire_completed_at || @company.updated_at || Time.current).iso8601
      (profile.keys & ProfileUpdater::PROFILE_KEYS).each do |key|
        provenance[key] ||= { "source" => source, "at" => at }
      end
      provenance
    end

    def retire_questionnaire_informed_analysis!
      runs = @company.document_analysis_runs.select { |run| questionnaire_informed?(run.profile_snapshot) }
      return if runs.empty?

      @company.company_knowledge_entries.active.where(document_analysis_run_id: runs.map(&:id))
              .update_all(status: "superseded", updated_at: Time.current)
      runs.each do |run|
        snapshot = run.profile_snapshot.to_h.deep_dup
        snapshot.delete("questionnaire_answers")
        MOVED_KEYS.each { |key| snapshot["company_profile"]&.delete(key) }
        run.update_columns(profile_snapshot: snapshot)
      end
    end

    def questionnaire_informed?(snapshot)
      snapshot = snapshot.to_h
      snapshot["questionnaire_answers"].present? ||
        MOVED_KEYS.any? { |key| snapshot.dig("company_profile", key).present? }
    end
  end
end
