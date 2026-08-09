# frozen_string_literal: true

module Companion
  # Classifies post-discovery inbound text. Fail-safe: low confidence → casual.
  class IntentClassifier
    INTENTS = %w[addendum ask tools share casual].freeze

    ADDENDUM_PHRASES = [
      /\badd (this|it|that) to (my )?(interview|discovery|report)\b/i,
      /\bfor (the |my )?(company )?report\b/i,
      /\bone more thing\b/i,
      /\bforgot to (mention|say|add)\b/i,
      /\balso want to add\b/i,
      /\bplease (include|add) this\b/i,
      /\bcount this (toward|towards|for)\b/i
    ].freeze

    TOOLS_PHRASES = [
      /\b(tool|tools|software|saas|app|apps|platform|platforms)\b/i,
      /\brecommend(ed|ation)?\b/i,
      /\bany (new )?tools?\b/i,
      /\bwhat (should|can) i (use|try)\b/i
    ].freeze

    ASK_PHRASES = [
      /\b(how|what|why|when|where|who)\b/i,
      /\b(can you|could you|help me|help with)\b/i,
      /\bdo you (know|remember)\b/i,
      /\?\s*$/
    ].freeze

    SHARE_PHRASES = [
      /\btoday i\b/i,
      /\bjust (finished|did|had|shared)\b/i,
      /\bwanted to share\b/i,
      /\bfyi\b/i,
      /\bwe (still |also )?(use|used|rely|manual|retype|chase)\b/i
    ].freeze

    AFFIRM_PHRASES = [
      /\A\s*(yes|yeah|yep|yup|sure|ok|okay|please|do it|add it|go ahead)\b/i
    ].freeze

    def self.call(text:, recent_messages: [], awaiting_promote_confirm: false)
      new(
        text: text,
        recent_messages: recent_messages,
        awaiting_promote_confirm: awaiting_promote_confirm
      ).call
    end

    def initialize(text:, recent_messages: [], awaiting_promote_confirm: false)
      @text = text.to_s.strip
      @recent_messages = Array(recent_messages)
      @awaiting_promote_confirm = awaiting_promote_confirm
    end

    def call
      return promote_confirm_result if @awaiting_promote_confirm && affirm?

      heuristic = heuristic_intent
      return heuristic if heuristic[:confidence] >= 0.7

      llm = llm_intent
      return llm if llm && INTENTS.include?(llm[:intent]) && llm[:confidence].to_f >= 0.55

      heuristic[:confidence] >= 0.45 ? heuristic : { intent: "casual", confidence: 0.4, source: "fail_safe" }
    end

    private

    def promote_confirm_result
      { intent: "promote_confirm", confidence: 0.95, source: "awaiting_affirm" }
    end

    def affirm?
      AFFIRM_PHRASES.any? { |re| re.match?(@text) }
    end

    def heuristic_intent
      return hit("addendum", 0.95, "phrase") if ADDENDUM_PHRASES.any? { |re| re.match?(@text) }
      return hit("tools", 0.9, "phrase") if TOOLS_PHRASES.any? { |re| re.match?(@text) }
      return hit("ask", 0.75, "phrase") if ASK_PHRASES.any? { |re| re.match?(@text) }
      return hit("share", 0.7, "phrase") if SHARE_PHRASES.any? { |re| re.match?(@text) }
      return hit("share", 0.55, "long_work_text") if long_workish?

      hit("casual", 0.5, "default")
    end

    def long_workish?
      @text.length > 80 && @text.match?(/\b(invoice|approval|excel|sap|workflow|manual|email|meeting|customer|ops|finance)\b/i)
    end

    def hit(intent, confidence, source)
      { intent: intent, confidence: confidence, source: source }
    end

    def llm_intent
      return nil unless Openai::Client.new.configured? || MocksAllowed.allowed?

      result = Openai::Client.new.classify_companion_intent(
        text: @text,
        recent_messages: @recent_messages
      )
      intent = result["intent"].to_s
      return nil unless INTENTS.include?(intent)

      { intent: intent, confidence: result["confidence"].to_f, source: "llm" }
    rescue Exception => e # rubocop:disable Lint/RescueException -- optional LLM must never break inbound routing
      Rails.logger.warn("[Companion::IntentClassifier] llm failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
