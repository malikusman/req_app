# frozen_string_literal: true

module Companies
  # Computes questionnaire completion percent and section touch state for a
  # v2 (questionnaire_version >= 2) company, against Companies::QuestionnaireV2Config.
  #
  # Completion counts only :essential-tier fields, matching what the frontend
  # computes for the v2 questionnaire (see computeCompletionPercent in
  # questionnaireOptions.ts). :recommended and :optional fields never affect
  # the percent. :conditional is excluded from the count for now too, since
  # its visibility-gated reveal isn't built yet — Stage 4 will revisit so it
  # counts only when its field is actually visible and its parent tier is
  # essential.
  class QuestionnaireV2Progress
    def self.call(answers)
      new(answers).call
    end

    def initialize(answers)
      @answers = (answers || {}).to_h.stringify_keys
    end

    def call
      answerable = Companies::QuestionnaireV2Config::TIERS[:essential].dup
      answered = answerable.count { |id| answered?(id) }
      percent = answerable.empty? ? 0 : ((answered.to_f / answerable.size) * 100).round
      {
        completion_percent: percent,
        answered_count: answered,
        answerable_count: answerable.size,
        section_status: section_status(answerable)
      }
    end

    private

    def section_status(answerable)
      Companies::QuestionnaireV2Config::STEP_FIELDS.transform_values do |ids|
        visible = ids.select { |id| answerable.include?(id) }
        touched = visible.any? { |id| answered?(id) }
        complete = visible.any? && visible.all? { |id| answered?(id) }
        { touched: touched, complete: complete }
      end
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