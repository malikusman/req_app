# frozen_string_literal: true

module Synthesis
  # One AiRun per model step of synthesis (Doc 10 §24): a P10 judgement of one
  # pair, or the P11 synthesis of the engagement, with the tokens and time of
  # every call it took. The same record as KeyPerson::RunLog, tied to the
  # synthesis run instead of a conversation.
  class RunLog
    def initialize(run:, stage:, prompt_version:, context_classes:)
      @run = run
      @stage = stage
      @prompt_version = prompt_version
      @context_classes = context_classes
      @results = []
    end

    def add(result)
      @results << result if result
    end

    def calls = @results.size

    def record!(status:, fallback_reason: nil)
      AiRun.create!(
        company_id: @run.company_id, engagement_id: @run.engagement_id, subject: @run,
        stage: @stage, prompt_version: @prompt_version, model: @results.last&.model,
        latency_ms: sum(:latency_ms), input_tokens: sum(:input_tokens), output_tokens: sum(:output_tokens),
        finish_reason: @results.last&.finish_reason, status: status, fallback_reason: fallback_reason,
        context_classes: @context_classes
      )
    rescue StandardError => e
      # The log must never cost the run its result.
      Rails.logger.warn("[Synthesis::RunLog] #{@stage} run=#{@run.id} not logged: #{e.class}: #{e.message}")
      nil
    end

    private

    def sum(attr)
      values = @results.filter_map(&attr)
      values.empty? ? nil : values.sum
    end
  end
end
