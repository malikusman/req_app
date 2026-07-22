# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discovery::ProcessTurnService do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company, department: "finance") }
  let(:conversation) do
    create(:conversation, employee: employee, status: "discovery", question_count: 1,
                          langgraph_thread_id: SecureRandom.uuid)
  end
  let(:client) { instance_double(Langgraph::Client) }

  before do
    create(:discovery_playbook, department: "finance")
    allow(Langgraph::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
  end

  describe "legacy single-agent path" do
    before do
      company.update!(settings: company.settings.merge("discovery_multi_agent_enabled" => false))
    end

    it "sends no multi_agent payload and persists the insight" do
      expect(client).to receive(:run_turn!).with(hash_including(multi_agent: nil)).and_return(
        "assistant_message" => "Next question?",
        "insight" => { "summary" => "Manual work in Excel", "topics" => ["tools"] },
        "completed" => false,
        "question_count" => 2
      )

      described_class.call(conversation: conversation, employee: employee, user_message: "I use Excel a lot")

      expect(conversation.reload.question_count).to eq(2)
      expect(conversation.conversation_insights.last.summary).to eq("Manual work in Excel")
      expect(conversation.blackboard).to eq({})
    end
  end

  describe "multi-agent path" do
    before do
      company.update!(settings: company.settings.merge("discovery_multi_agent_enabled" => true))
    end

    let(:returned_blackboard) do
      {
        "agent_queue" => [{ "id" => "domain_finance", "priority" => 1, "question_budget" => 4 }],
        "agent_states" => { "domain_finance" => { "questions_asked" => 1, "question_budget" => 4, "status" => "active" } },
        "shared_findings" => [{ "agent" => "domain_finance", "finding" => "SAP re-entry", "confidence" => 0.7, "turn" => 2 }],
        "active_agent_id" => "domain_finance"
      }
    end

    it "passes the multi-agent payload and persists the returned blackboard" do
      inbound = create(:message, conversation: conversation, direction: "inbound", message_type: "text")
      expect(client).to receive(:run_turn!) do |args|
        expect(args[:multi_agent]).to include(:profile, :blackboard, :limits, :media_context, :media_snippets)
        expect(args[:multi_agent][:limits][:max_followup_depth]).to eq(2)
        {
          "assistant_message" => "Walk me through month-end close.",
          "insight" => { "summary" => "Insight", "topics" => ["daily_workflow"] },
          "completed" => false,
          "question_count" => 2,
          "blackboard" => returned_blackboard,
          "active_agent_id" => "domain_finance",
          "routing_decision" => { "action" => "continue", "agent" => "domain_finance", "reason" => "budget remaining" }
        }
      end

      described_class.call(
        conversation: conversation,
        employee: employee,
        user_message: "It's mostly SAP",
        inbound_message: inbound
      )

      conversation.reload
      expect(conversation.blackboard["active_agent_id"]).to eq("domain_finance")
      expect(conversation.blackboard["shared_findings"].size).to eq(1)
      expect(conversation.state_snapshot["last_routing_decision"]["action"]).to eq("continue")
    end

    it "persists the final blackboard and finalizes on completion" do
      expect(client).to receive(:run_turn!).and_return(
        "assistant_message" => "Thank you!",
        "insight" => { "summary" => "Wrap", "topics" => [] },
        "completed" => true,
        "question_count" => 1,
        "blackboard" => returned_blackboard
      )

      expect do
        described_class.call(conversation: conversation, employee: employee, user_message: "That's all")
      end.to have_enqueued_job(MemoryPromotionJob)

      conversation.reload
      expect(conversation.status).to eq("completed")
      expect(conversation.blackboard["shared_findings"].size).to eq(1)
    end

    it "uses the conversation effective question target after reopen" do
      conversation.update!(
        status: "discovery",
        question_count: 10,
        state_snapshot: conversation.state_snapshot.merge("question_target" => 13)
      )

      expect(client).to receive(:run_turn!) do |args|
        expect(args[:context][:question_target]).to eq(13)
        expect(args[:context][:question_count]).to eq(10)
        {
          "assistant_message" => "Tell me more about that approval?",
          "insight" => { "summary" => "Late detail on approvals", "topics" => ["approvals"] },
          "completed" => false,
          "question_count" => 11,
          "blackboard" => returned_blackboard
        }
      end

      described_class.call(
        conversation: conversation,
        employee: employee,
        user_message: "Also, CFO sign-off takes two weeks"
      )

      expect(conversation.reload.conversation_insights.last.summary).to eq("Late detail on approvals")
    end

    it "re-finalizes after an addendum and re-enqueues aggregation" do
      employee.update!(participation_status: "completed", completed_at: 1.day.ago)
      conversation.update!(
        status: "discovery",
        question_count: 11,
        state_snapshot: { "question_target" => 13, "addendum_count" => 1 }
      )

      expect(client).to receive(:run_turn!).and_return(
        "assistant_message" => "Thanks again!",
        "insight" => { "summary" => "Addendum insight", "topics" => ["approvals"] },
        "completed" => true,
        "question_count" => 12,
        "blackboard" => returned_blackboard
      )

      expect do
        described_class.call(
          conversation: conversation,
          employee: employee,
          user_message: "That was the missing piece"
        )
      end.to have_enqueued_job(AggregateIntelligenceJob)
        .and have_enqueued_job(MemoryPromotionJob)

      expect(conversation.reload.status).to eq("completed")
      expect(conversation.conversation_insights.last.summary).to eq("Addendum insight")
    end

    it "does not trip the breaker or defer on non-retryable agent errors" do
      expect(client).to receive(:run_turn!).and_raise(
        Langgraph::UnavailableError.new("bad_payload", retryable: false)
      )
      expect(OpenaiCircuitBreaker).not_to receive(:trip!)
      expect(RetryDiscoveryTurnJob).not_to receive(:set)

      result = described_class.call(
        conversation: conversation,
        employee: employee,
        user_message: "hello"
      )

      expect(result["delayed"]).to eq(true)
    end
  end
end
