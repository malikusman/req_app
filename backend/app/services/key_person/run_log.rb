# frozen_string_literal: true

module KeyPerson
  # One AiRun per model step of the conversation (Doc 08 §30): a P02 turn, a P03
  # capture or a P04 context, with the tokens and time of every call it took.
  class RunLog
    def initialize(session:, stage:, prompt_version:, context_classes:, subject: nil)
      @session = session
      @stage = stage
      @prompt_version = prompt_version
      @context_classes = context_classes
      @subject = subject || session
      @results = []
    end

    def add(result)
      @results << result if result
    end

    def calls = @results.size

    def record!(status:, fallback_reason: nil)
      AiRun.create!(
        company_id: @session.company_id, engagement_id: @session.engagement_id, subject: @subject,
        stage: @stage, prompt_version: @prompt_version, model: @results.last&.model,
        latency_ms: sum(:latency_ms), input_tokens: sum(:input_tokens), output_tokens: sum(:output_tokens),
        finish_reason: @results.last&.finish_reason, status: status, fallback_reason: fallback_reason,
        context_classes: @context_classes
      )
    rescue StandardError => e
      # The log must never cost the participant their turn.
      Rails.logger.warn("[KeyPerson::RunLog] #{@stage} session=#{@session.id} not logged: #{e.class}: #{e.message}")
      nil
    end

    private

    def sum(attr)
      values = @results.filter_map(&attr)
      values.empty? ? nil : values.sum
    end
  end
end
