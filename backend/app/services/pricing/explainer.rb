# frozen_string_literal: true

module Pricing
  # P24: explains a proposed Stage 1 fee to the administrator and writes the
  # client's scope statement, from figures the platform computed (P24, Doc 17
  # §16 — the model explains, never prices).
  #
  # Runs once per proposed version, in the background. A reply that won't parse
  # gets one reformat retry; one that fails the checks (ExplanationValidator) is
  # dropped. Either way the administrator still sees the computed derivation
  # and can approve, and the client reads the template scope statement — the
  # fallback is recorded on the quote and in the AiRun (P24 §7, Doc 05 §16).
  #
  # The validity line always comes from the template, which dates it from the
  # quote; and nothing is written to a quote no longer with the administrator,
  # so the client's text never changes after it is issued.
  class Explainer
    def self.call(quote, client: Pricing.client_for(quote.company))
      new(quote, client: client).call
    end

    def self.system_prompt
      [Openai::Client.prompt("p00a_analytical_base.v1.txt").strip,
       Openai::Client.prompt("p24_stage1_price_explainer.v1.txt").strip].join("\n\n")
    end

    def initialize(quote, client:)
      @quote = quote
      @client = client
      @results = []
    end

    def call
      return @quote unless @quote.proposed? && @quote.admin_explanation.blank?

      reply, reason = from_model
      if reply
        admin, client = ExplanationValidator.new(reply, @quote).call
        save!(admin, client)
        log!(@results.size > 1 ? "RETRIED" : "OK")
      else
        fallback!(reason)
      end
      @quote
    rescue ExplanationValidator::Invalid => e
      fallback!("failed_checks", detail: e.message)
      @quote
    end

    private

    def from_model
      return [nil, "model_off"] unless Llm::Pricing.enabled? && @client.configured?
      # The breaker guards the real model; scripted replies don't need it.
      return [nil, "model_unavailable"] if !@client.is_a?(ScriptedClient) && OpenaiCircuitBreaker.open?

      2.times do
        result = @client.stage1_price_explanation(system: self.class.system_prompt, context: Stage1Context.build(@quote))
        @results << result
        raw = @client.parse_reply(result.content)
        return [raw, nil] if raw.is_a?(Hash)
      rescue JSON::ParserError
        next
      end
      [nil, "unusable_reply"]
    rescue Openai::Client::Error, Timeout::Error, SystemCallError, IOError => e
      Rails.logger.warn("[Pricing::Explainer] quote=#{@quote.id} #{e.class}: #{e.message}")
      [nil, "model_error"]
    end

    def save!(admin, client)
      @quote.with_lock do
        next unless @quote.proposed?

        scope = client.merge("validity" => ScopeTemplate.call(@quote)["validity"])
        @quote.update!(admin_explanation: admin, client_scope: scope, explanation_source: "P24")
        @quote.record!("explained", detail: { prompt_version: Openai::Client::STAGE1_PRICE_EXPLAINER_PROMPT_VERSION })
      end
    end

    def fallback!(reason, detail: nil)
      @quote.record!("explanation_fallback", detail: { reason: reason, detail: detail }.compact)
      log!("FALLBACK", fallback_reason: reason)
    end

    def log!(status, fallback_reason: nil)
      AiRun.create!(
        company_id: @quote.company_id, engagement_id: @quote.engagement_id, subject: @quote, stage: "P24",
        prompt_version: Openai::Client::STAGE1_PRICE_EXPLAINER_PROMPT_VERSION, model: @results.last&.model,
        latency_ms: sum(:latency_ms), input_tokens: sum(:input_tokens), output_tokens: sum(:output_tokens),
        finish_reason: @results.last&.finish_reason, status: status, fallback_reason: fallback_reason,
        context_classes: Stage1Context::BLOCKS
      )
    rescue StandardError => e
      Rails.logger.warn("[Pricing::Explainer] quote=#{@quote.id} not logged: #{e.class}: #{e.message}")
    end

    def sum(attr)
      values = @results.filter_map(&attr)
      values.empty? ? nil : values.sum
    end
  end
end
