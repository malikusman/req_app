# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companion::PostDiscoveryRouter do
  let(:company) { create(:company) }
  let(:employee) do
    create(:employee, company: company, onboarding_step: "verified", participation_status: "completed")
  end
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed", question_count: 10)
  end
  let(:meta_client) { instance_double(Whatsapp::MetaClient, configured?: false) }

  before do
    allow(Openai::Client).to receive(:new).and_return(
      instance_double(
        Openai::Client,
        configured?: true,
        companion_chat: { "reply" => "Happy to help." },
        classify_companion_intent: { "intent" => "casual", "confidence" => 0.2 },
        companion_general_tools: {
          "suggestions" => [{ "name" => "Notion", "why" => "SOPs" }]
        }
      )
    )
  end

  it "keeps conversation completed for casual companion chat" do
    described_class.call(
      conversation: conversation,
      employee: employee,
      user_message: "thanks!",
      channel: "whatsapp",
      client: meta_client
    )

    expect(conversation.reload.status).to eq("completed")
    outbound = conversation.messages.where(direction: "outbound").last
    expect(outbound.body).to be_present
    expect(outbound.agent_id).to eq("companion")
    expect(outbound.is_discovery_question).to eq(false)
  end

  it "reopens discovery for clear addendum intent" do
    create(:discovery_playbook, department: employee.department.presence || "default")
    allow(Discovery::ProcessTurnService).to receive(:call).and_return(
      "assistant_message" => "Got it — tell me more.",
      "completed" => false,
      "question_count" => 11,
      "insight" => {}
    )

    described_class.call(
      conversation: conversation,
      employee: employee,
      user_message: "One more thing about approvals",
      channel: "whatsapp",
      client: meta_client
    )

    expect(conversation.reload.status).to eq("discovery")
    expect(Discovery::ProcessTurnService).to have_received(:call)
  end

  it "prompts to promote on share intent and promotes on yes" do
    create(:discovery_playbook, department: employee.department.presence || "default")
    allow(Discovery::ProcessTurnService).to receive(:call).and_return(
      "assistant_message" => "Added.",
      "completed" => false,
      "question_count" => 11,
      "insight" => {}
    )

    described_class.call(
      conversation: conversation,
      employee: employee,
      user_message: "Today I spent 2 hours retyping POD notes into Excel",
      channel: "whatsapp",
      client: meta_client
    )

    expect(conversation.reload.status).to eq("completed")
    expect(Companion::NoteStore.awaiting_promote_confirm?(conversation)).to eq(true)
    expect(conversation.messages.where(direction: "outbound").last.body).to include("company report")

    described_class.call(
      conversation: conversation,
      employee: employee,
      user_message: "yes",
      channel: "whatsapp",
      client: meta_client
    )

    expect(conversation.reload.status).to eq("discovery")
    expect(Discovery::ProcessTurnService).to have_received(:call)
  end

  it "answers tools with catalog-first formatting" do
    described_class.call(
      conversation: conversation,
      employee: employee,
      user_message: "Any tools for invoice matching?",
      channel: "whatsapp",
      client: meta_client
    )

    expect(conversation.reload.status).to eq("completed")
    body = conversation.messages.where(direction: "outbound").last.body
    expect(body).to match(/company catalog|Not from your company catalog|general ideas/i)
  end
end
