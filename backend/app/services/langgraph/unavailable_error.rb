# frozen_string_literal: true

module Langgraph
  class UnavailableError < StandardError
    attr_reader :retryable

    def initialize(message = "LangGraph unavailable", retryable: true)
      super(message)
      @retryable = retryable
    end
  end
end
