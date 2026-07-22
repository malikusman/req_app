# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discovery::ReopenConversationService do
  let(:company) { create(:company) }
  let(:employee) do
    create(:employee, company: company, participation_status: "completed", onboarding_step: "verified")
  end
  let(:conversation) do
    create(
      :conversation,
      employee: employee,
      company: company,
      status: "completed",
      question_count: 10,
      state_snapshot: {
        "question_target" => 10,
        "blackboard" => {
          "active_agent_id" => "domain_finance",
          "agent_queue" => [{ "id" => "domain_finance", "priority" => 1, "question_budget" => 5 }],
          "agent_states" => {
            "domain_finance" => {
              "questions_asked" => 5,
              "question_budget" => 5,
              "status" => "complete",
              "open_threads" => []
            }
          },
          "conversation_summary" => "Prior interview notes.",
          "total_budget" => 10
        }
      }
    )
  end

  it "is a no-op when the conversation is not completed" do
    conversation.update!(status: "discovery")
    expect do
      described_class.call(conversation: conversation, employee: employee)
    end.not_to change { conversation.reload.state_snapshot["addendum_count"] }
  end

  it "reopens discovery with a bounded question-target top-up and agent budget" do
    result = described_class.call(conversation: conversation, employee: employee)

    expect(result.status).to eq("discovery")
    expect(result.effective_question_target).to eq(13)
    expect(result.state_snapshot["addendum_count"]).to eq(1)
    expect(result.blackboard["conversation_summary"]).to include(
      "Employee volunteered additional info after completion."
    )

    agent = result.blackboard.dig("agent_states", "domain_finance")
    expect(agent["status"]).to eq("active")
    expect(agent["question_budget"]).to eq(8) # 5 asked + 3 budget
    expect(result.blackboard["active_agent_id"]).to eq("domain_finance")
  end

  it "records a conversation_reopened timeline event" do
    expect do
      described_class.call(conversation: conversation, employee: employee)
    end.to change(InsightTimelineEvent, :count).by(1)

    event = InsightTimelineEvent.last
    expect(event.event_type).to eq("conversation_reopened")
    expect(event.company_id).to eq(company.id)
    expect(event.target_id).to eq(employee.id)
  end

  it "respects a custom discovery_addendum_budget" do
    company.update!(settings: company.settings.merge("discovery_addendum_budget" => 5))
    described_class.call(conversation: conversation, employee: employee)
    expect(conversation.reload.effective_question_target).to eq(15)
  end
end
