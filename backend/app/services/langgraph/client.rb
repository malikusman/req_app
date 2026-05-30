# frozen_string_literal: true

require "net/http"
require "json"

module Langgraph
  class Client
    def initialize(base_url: ENV.fetch("LANGGRAPH_URL", "http://langgraph:8000"))
      @base_url = base_url.chomp("/")
    end

    def create_thread!
      response = post("/v1/threads", {})
      response.fetch("thread_id")
    end

    def run_turn!(thread_id:, user_message:, playbook:, context:, history:, use_v2: false)
      body = {
        user_message: user_message,
        playbook: {
          prompt_block: playbook.prompt_block,
          version: playbook.version,
          department: playbook.department
        },
        context: context,
        history: history,
        use_v2: use_v2
      }

      path = use_v2 ? "/v1/threads/#{thread_id}/discovery/turn" : "/v1/threads/#{thread_id}/turn"
      post(path, body)
    rescue UnavailableError
      raise
    rescue StandardError => e
      raise UnavailableError, e.message
    end

    def reviewer_chat!(thread_id:, company_id:, user_message:, history:)
      post("/v1/threads/#{thread_id}/reviewer/chat", {
        company_id: company_id,
        user_message: user_message,
        history: history
      })
    end

    def generate_report!(thread_id:, company_id:, snapshot:)
      post("/v1/threads/#{thread_id}/report/generate", {
        company_id: company_id,
        snapshot: snapshot
      })
    end

    def scout_opportunities!(thread_id:, company_id:, solution_catalog:)
      post("/v1/threads/#{thread_id}/opportunity/scout", {
        company_id: company_id,
        solution_catalog: solution_catalog
      })
    end

    def resume!(thread_id:, resolution:)
      post("/v1/threads/#{thread_id}/resume", { resolution: resolution })
    end

    private

    def post(path, body)
      uri = URI.parse("#{@base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 120

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.to_json

      response = http.request(request)
      parsed = JSON.parse(response.body)

      if response.code.to_i == 503
        raise UnavailableError, parsed.dig("detail", "error") || "openai_unavailable"
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise UnavailableError, parsed["detail"] || parsed["error"] || "request_failed"
      end

      parsed
    end
  end
end
