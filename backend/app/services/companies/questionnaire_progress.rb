# frozen_string_literal: true

module Companies
  # Completion percent and per-step touch state for the onboarding questionnaire.
  #
  # Only Essential fields count toward the percent. Recommended and Optional
  # questions are worth asking but must never hold the bar at 99% — the client was
  # explicit that they should not pressure anyone into answering.
  class QuestionnaireProgress
    Config = Companies::QuestionnaireConfig

    # Kept as constants so callers that referenced them keep working.
    FIELD_IDS = Config::FIELD_IDS
    STEP_FIELDS = Config::STEP_FIELDS

    def self.call(answers)
      new(answers).call
    end

    def initialize(answers)
      @answers = (answers || {}).to_h.stringify_keys
    end

    def call
      counted = countable_fields
      answered = counted.count { |id| answered?(id) }
      percent = counted.empty? ? 0 : ((answered.to_f / counted.size) * 100).round

      {
        completion_percent: percent,
        answered_count: answered,
        answerable_count: counted.size,
        section_status: STEP_FIELDS.transform_values do |ids|
          visible = ids.select { |id| Config.visible?(id, @answers) }
          # Touch state covers every visible question in the step, not just the
          # Essential ones: a step where someone answered only the optional
          # question has still been visited, and showing it as untouched would be
          # a lie about their own work.
          answered_here = visible.select { |id| answered?(id) }
          required = visible.select { |id| Config::TIERS_BY_KEY[id] == :essential }
          {
            touched: answered_here.any?,
            complete: required.any? && required.all? { |id| answered?(id) }
          }
        end
      }
    end

    private

    # Essential only, and only where currently visible — a conditional question
    # that is hidden must not count as missing, or the percent could never reach
    # 100 for a company the question does not apply to.
    def countable_fields
      Config::ESSENTIAL_KEYS.select { |id| Config.visible?(id, @answers) }
    end

    def answered?(id)
      value = @answers[id]
      case value
      when nil then false
      when String then value.strip.present?
      when Array then value.any? { |v| v.to_s.strip.present? }
      when Hash
        # The two-stage and per-item questions store a hash. A key whose value is
        # blank is a row the user opened and left empty, not an answer.
        value.any? { |_k, v| v.is_a?(Array) ? v.any? { |x| x.to_s.strip.present? } : v.to_s.strip.present? }
      else value.present?
      end
    end
  end
end
