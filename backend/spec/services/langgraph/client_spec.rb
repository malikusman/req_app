# frozen_string_literal: true

require "rails_helper"

RSpec.describe Langgraph::Client do
  subject(:client) { described_class.new(base_url: "http://langgraph.test") }

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
  end
end
