# frozen_string_literal: true

require "rails_helper"

# OpenaiCircuitBreaker.trip! is a setex, so tripping an already-open breaker
# refreshes its TTL. Every request the breaker rejects used to re-trip it, which
# meant a 300s cool-off never expired while traffic continued — a transient model
# outage became a permanent one.
RSpec.describe "Discovery turn: the circuit breaker must be able to reopen" do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "discovery",
                          langgraph_thread_id: SecureRandom.uuid)
  end

  before { create(:discovery_playbook, department: "default") if DiscoveryPlaybook.count.zero? }

  def process
    Discovery::ProcessTurnService.call(
      conversation: conversation, employee: employee, user_message: "hello", defer_on_failure: false
    )
  end

  it "does not extend the cool-off window on a request it rejects" do
    OpenaiCircuitBreaker.trip!(ttl: 60)
    expect(OpenaiCircuitBreaker).not_to receive(:trip!)

    result = process

    expect(result["delayed"]).to be(true)
  end

  it "still trips a closed breaker on a retryable failure" do
    OpenaiCircuitBreaker.reset!
    allow_any_instance_of(Langgraph::Client)
      .to receive(:run_turn!).and_raise(Langgraph::UnavailableError.new("timeout", retryable: true))

    process

    expect(OpenaiCircuitBreaker.open?).to be(true)
  end

  it "does not trip on a non-retryable failure" do
    OpenaiCircuitBreaker.reset!
    allow_any_instance_of(Langgraph::Client)
      .to receive(:run_turn!).and_raise(Langgraph::UnavailableError.new("bad request", retryable: false))

    process

    expect(OpenaiCircuitBreaker.open?).to be(false)
  end
end
