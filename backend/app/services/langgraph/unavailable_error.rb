# frozen_string_literal: true

module Langgraph
  class UnavailableError < StandardError
    attr_reader :retryable, :code

    def initialize(message = "LangGraph unavailable", retryable: true, code: "openai_unavailable")
      super(message)
      @retryable = retryable
      @code = code
    end
  end
end
