# frozen_string_literal: true

require "rails_helper"

RSpec.describe Langgraph::Client do
  subject(:client) { described_class.new(base_url: "http://langgraph.test") }

  describe "#generate_deep_dive_plan!" do
    it "sends the scoped context to the internal authenticated planning endpoint" do
      context = { "task_id" => "proposal-10" }
      request = stub_request(:post, "http://langgraph.test/v1/consultant/deep_dive/plan")
                .with(body: { context: context }.to_json,
                      headers: { "X-Internal-Token" => ENV.fetch("INTERNAL_API_TOKEN", "dev-internal-token") })
                .to_return(status: 200, body: { generated_by: "llm", plan: {} }.to_json)

      expect(client.generate_deep_dive_plan!(context: context)).to include("generated_by" => "llm")
      expect(request).to have_been_requested.once
    end
  end

  describe "#run_turn!" do
    let(:playbook) do
      instance_double(
        DiscoveryPlaybook,
        prompt_block: "Ask about workflows.",
        version: 1,
        department: "finance"
      )
    end

    def stub_turn(status:, body:)
      stub_request(:post, "http://langgraph.test/v1/threads/thread-1/turn")
        .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "returns the parsed body on success" do
      stub_turn(status: 200, body: { "assistant_message" => "Hi", "completed" => false })

      result = client.run_turn!(
        thread_id: "thread-1",
        user_message: "hello",
        playbook: playbook,
        context: {},
        history: []
      )

      expect(result["assistant_message"]).to eq("Hi")
    end

    it "marks 4xx responses as non-retryable" do
      stub_turn(status: 422, body: { "detail" => "bad_payload" })

      expect do
        client.run_turn!(
          thread_id: "thread-1",
          user_message: "hello",
          playbook: playbook,
          context: {},
          history: []
        )
      end.to raise_error(Langgraph::UnavailableError) { |error|
        expect(error.retryable).to eq(false)
        expect(error.message).to eq("bad_payload")
      }
    end

    it "marks 5xx responses as retryable" do
      stub_turn(status: 503, body: { "detail" => { "error" => "openai_unavailable" } })

      expect do
        client.run_turn!(
          thread_id: "thread-1",
          user_message: "hello",
          playbook: playbook,
          context: {},
          history: []
        )
      end.to raise_error(Langgraph::UnavailableError) { |error|
        expect(error.retryable).to eq(true)
        expect(error.message).to eq("openai_unavailable")
      }
    end

    it "preserves non-retryable provider failures and their reason across a 503" do
      stub_turn(status: 503, body: { detail: { error: "openai_quota_exceeded", retryable: false,
                                            reason: "OpenAI organization quota or spend limit exhausted" } })
      expect {
        client.run_turn!(thread_id: "thread-1", user_message: "outlook, Excel and our system",
                         playbook: playbook, context: {}, history: [])
      }.to raise_error(Langgraph::UnavailableError) { |error|
        expect(error.retryable).to be(false)
        expect(error.code).to eq("openai_quota_exceeded")
        expect(error.message).to include("spend limit exhausted")
      }
    end

    it "keeps transport timeouts retryable" do
      stub_request(:post, "http://langgraph.test/v1/threads/thread-1/turn").to_timeout
      expect {
        client.run_turn!(thread_id: "thread-1", user_message: "helping the HR?",
                         playbook: playbook, context: {}, history: [])
      }.to raise_error(Langgraph::UnavailableError) { |error| expect(error.retryable).to be(true) }
    end
  end
end
