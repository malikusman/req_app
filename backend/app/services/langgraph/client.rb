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

    def run_turn!(thread_id:, user_message:, playbook:, context:, history:)
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

      post("/v1/threads/#{thread_id}/turn", body)
    rescue UnavailableError
      raise
    rescue StandardError => e
      raise UnavailableError, e.message
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
