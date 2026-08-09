# frozen_string_literal: true

require "rails_helper"

RSpec.describe Web::TurnRouter do
  let(:company) { create(:company) }
  let(:employee) do
    create(:employee, company: company, onboarding_step: "verified", participation_status: "completed")
  end
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed", question_count: 10)
  end

  it "uses companion routing after completion (does not auto-reopen on casual share)" do
    allow(Openai::Client).to receive(:new).and_return(
      instance_double(
        Openai::Client,
        configured?: true,
        companion_chat: { "reply" => "Noted — happy to help." },
        classify_companion_intent: { "intent" => "casual", "confidence" => 0.2 },
        companion_general_tools: { "suggestions" => [] }
      )
    )

    described_class.handle_text(
      employee: employee,
      conversation: conversation,
      text: "thanks for earlier"
    )

    expect(conversation.reload.status).to eq("completed")
    expect(conversation.messages.where(direction: "outbound").last.agent_id).to eq("companion")
  end

  it "reopens when the employee asks to add to the interview" do
    create(:discovery_playbook, department: employee.department.presence || "default")

    allow(Discovery::ProcessTurnService).to receive(:call).and_return(
      "assistant_message" => "Got it — anything else?",
      "insight" => { "summary" => "Web addendum", "topics" => ["tools"] },
      "completed" => false,
      "question_count" => 11
    )

    described_class.handle_text(
      employee: employee,
      conversation: conversation,
      text: "Please add this to my interview: we also use a shared spreadsheet for handoffs"
    )

    expect(conversation.reload.status).to eq("discovery")
    expect(conversation.state_snapshot["addendum_count"]).to eq(1)
    expect(Discovery::ProcessTurnService).to have_received(:call)
  end
end
