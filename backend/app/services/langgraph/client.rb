# frozen_string_literal: true

require "net/http"
require "json"

module Langgraph
  class Client
    READ_TIMEOUT = Integer(ENV.fetch("LANGGRAPH_READ_TIMEOUT", "45"))

    def initialize(base_url: ENV.fetch("LANGGRAPH_URL", "http://langgraph:8000"))
      @base_url = base_url.chomp("/")
    end

    def create_thread!
      response = post("/v1/threads", {})
      response.fetch("thread_id")
    end

    def run_turn!(thread_id:, user_message:, playbook:, context:, history:, multi_agent: nil)
      body = {
        user_message: user_message,
        playbook: {
          prompt_block: playbook.prompt_block,
          version: playbook.version,
          department: playbook.department
        },
        context: context,
        history: history
      }

      if multi_agent
        body[:multi_agent] = true
        body[:profile] = multi_agent[:profile]
        body[:blackboard] = multi_agent[:blackboard]
        body[:limits] = multi_agent[:limits]
        body[:memory_facts] = multi_agent[:memory_facts] || []
        body[:document_snippets] = multi_agent[:document_snippets] || []
        body[:knowledge_snippets] = multi_agent[:knowledge_snippets] || []
        body[:media_context] = multi_agent[:media_context]
        body[:media_snippets] = multi_agent[:media_snippets] || []
        body[:company_profile] = multi_agent[:company_profile] if multi_agent[:company_profile].present?
      end

      post("/v1/threads/#{thread_id}/turn", body)
    rescue Langgraph::UnavailableError
      raise
    rescue StandardError => e
      raise Langgraph::UnavailableError.new(e.message, retryable: true)
    end

    def run_docs_analysis!(payload)
      post(
        "/v1/docs_analysis/runs",
        payload,
        read_timeout: Integer(ENV.fetch("LANGGRAPH_DOCS_READ_TIMEOUT", "180"))
      )
    rescue Langgraph::UnavailableError
      raise
    rescue StandardError => e
      raise Langgraph::UnavailableError.new(e.message, retryable: true)
    end

    private

    def post(path, body, read_timeout: READ_TIMEOUT)
      uri = URI.parse("#{@base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = read_timeout

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.to_json

      response = http.request(request)
      parsed = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        {}
      end

      code = response.code.to_i
      if code == 503 || code >= 500
        raise Langgraph::UnavailableError.new(
          parsed.dig("detail", "error") || parsed["detail"] || parsed["error"] || "openai_unavailable",
          retryable: true
        )
      end

      if code >= 400
        raise Langgraph::UnavailableError.new(
          parsed["detail"] || parsed["error"] || "agent_request_failed_#{code}",
          retryable: false
        )
      end

      parsed
    end
  end
end
