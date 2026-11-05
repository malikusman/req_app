require "rails_helper"

RSpec.describe "Workflow interview reliability" do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, department: "finance") }
  let(:conversation) { create(:conversation, employee: employee, status: "discovery", langgraph_thread_id: SecureRandom.uuid) }
  let(:inbound) { create(:message, conversation: conversation, direction: "inbound", channel: "web", body: "I match payments in SAP") }
  let(:client) { instance_double(Langgraph::Client) }
  let(:result) { { "assistant_message" => "What happens to unmatched payments?", "question_count" => 1, "completed" => false } }

  before do
    create(:discovery_playbook, department: "finance")
    allow(Langgraph::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
  end

  def process
    Discovery::ProcessTurnService.call(conversation: conversation, employee: employee,
      user_message: inbound.body, inbound_message: inbound)
  end

  it "processes a saved answer once and preserves its identity for evidence" do
    expect(client).to receive(:run_turn!).once do |payload|
      expect(payload[:multi_agent][:source_message_id]).to eq(inbound.id)
      expect(payload[:history]).to include(hash_including(message_id: inbound.id))
      result
    end
    first = process
    second = process
    expect(first).to eq(second)
    expect(second["source_message_id"]).to eq(inbound.id)
    expect(conversation.reload.question_count).to eq(1)
  end

  it "persists only one assistant reply when recovery delivers twice" do
    identified = result.merge("source_message_id" => inbound.id)
    2.times { Discovery::DeliverReply.call(conversation: conversation, employee: employee, result: identified, channel: :web) }
    expect(conversation.messages.where(direction: "outbound").count).to eq(1)
  end

  it "delivers background recovery to the original web channel" do
    allow(Discovery::ProcessTurnService).to receive(:call).and_return(result)
    expect(Discovery::DeliverReply).to receive(:call).with(hash_including(channel: :web))
    RetryDiscoveryTurnJob.perform_now(conversation.id, inbound.body, inbound.id)
  end

  it "waits for the breaker without consuming the provider retry budget" do
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(true)
    allow(OpenaiCircuitBreaker).to receive(:retry_after).and_return(240)
    expect(Discovery::ProcessTurnService).not_to receive(:call)
    expect { RetryDiscoveryTurnJob.perform_now(conversation.id, inbound.body, inbound.id, 2) }
      .to have_enqueued_job(RetryDiscoveryTurnJob).with(conversation.id, inbound.body, inbound.id, 2)
  end

  it "does not recursively enqueue retries from a retry job" do
    allow(client).to receive(:run_turn!).and_raise(Langgraph::UnavailableError.new("unavailable", retryable: true))
    expect {
      Discovery::ProcessTurnService.call(conversation: conversation, employee: employee,
        user_message: inbound.body, inbound_message: inbound, defer_on_failure: false)
    }.not_to have_enqueued_job(RetryDiscoveryTurnJob)
  end

  it "does not publish successful findings or complete the employee after a stalled exit" do
    conversation.update!(state_snapshot: { "blackboard" => { "dossier" => { "workflow" => { "outcome" => "needs_follow_up" } } } })
    expect {
      Discovery::FinalizeConversationService.call(conversation: conversation, employee: employee)
    }.not_to have_enqueued_job(BuildFindingsJob)
    expect(employee.reload.participation_status).not_to eq("completed")
    expect(company.reload.conversation_count).to eq(0)
  end

  it "invalidates summary confirmation when an interview is reopened" do
    conversation.update!(status: "completed", state_snapshot: { "blackboard" => { "dossier" => {
      "workflow" => { "revision" => 2, "confirmation" => { "revision" => 2 }, "outcome" => "successful" }
    } } })
    Discovery::ReopenConversationService.call(conversation: conversation, employee: employee)
    expect(conversation.reload.dossier.dig("workflow", "confirmation")).to be_nil
    expect(conversation.dossier.dig("workflow", "outcome")).to be_nil
  end

  it "rejects successful completion without confirmation of the current summary" do
    allow(client).to receive(:run_turn!).and_return(result.merge("completed" => true,
      "blackboard" => { "dossier" => { "workflow" => { "version" => 1, "outcome" => "successful",
        "revision" => 2, "confirmation" => { "revision" => 1 }, "tasks" => [] } } }))
    response = process
    expect(response["delayed"]).to be(true)
    expect(response["retryable"]).to be(false)
    expect(conversation.reload.status).to eq("discovery")
    expect(employee.reload.participation_status).not_to eq("completed")
  end

  it "saves a confirmed workflow profile and finalizes the employee once" do
    confirmed = result.merge("completed" => true, "assistant_message" => "Your workflow summary is confirmed and saved.",
      "blackboard" => { "dossier" => { "workflow" => { "version" => 1, "outcome" => "successful",
        "revision" => 2, "tasks" => [{ "id" => "task-1", "name" => "Invoice processing" }],
        "confirmation" => { "revision" => 2, "summary_sha256" => "confirmed-summary-digest", "summary_message_id" => 600 } } } })
    expect(client).to receive(:run_turn!).once.and_return(confirmed)
    expect { 2.times { process } }.to have_enqueued_job(BuildDiscoveryPackageJob).with(conversation.id).once
    expect(conversation.reload.status).to eq("completed")
    expect(conversation.dossier.dig("workflow", "outcome")).to eq("successful")
    expect(conversation.dossier.dig("workflow", "confirmation", "summary_message_id")).to eq(600)
    expect(employee.reload.participation_status).to eq("completed")
    expect(company.reload.conversation_count).to eq(1)
  end
end
