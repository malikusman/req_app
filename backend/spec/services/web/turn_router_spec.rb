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

  it "reopens a completed conversation and processes an addendum message" do
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
      text: "We also use a shared spreadsheet for handoffs"
    )

    expect(conversation.reload.status).to eq("discovery")
    expect(conversation.state_snapshot["addendum_count"]).to eq(1)
    expect(Discovery::ProcessTurnService).to have_received(:call)
  end
end
