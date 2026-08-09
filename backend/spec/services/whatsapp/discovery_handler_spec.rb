# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::DiscoveryHandler do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) { create(:conversation, employee: employee, status: "discovery", question_count: 1) }
  let(:meta_client) { instance_double(Whatsapp::MetaClient, configured?: false) }

  subject(:handler) { described_class.new(employee: employee, conversation: conversation, client: meta_client) }

  describe "#deliver_assistant_reply" do
    it "persists agent provenance on outbound discovery questions" do
      handler.deliver_assistant_reply(
        "assistant_message" => "Walk me through your morning routine.",
        "completed" => false,
        "question_count" => 2,
        "routing_decision" => {
          "action" => "continue",
          "agent" => "domain_finance",
          "reason" => "budget remaining"
        }
      )

      outbound = conversation.messages.where(direction: "outbound").last
      expect(outbound.agent_id).to eq("domain_finance")
      expect(outbound.routing_decision["action"]).to eq("continue")
      expect(outbound.is_discovery_question).to be(true)
    end
  end

  describe "#handle_inbound_text" do
    it "routes completed conversations through companion (no auto-reopen for casual)" do
      employee.update!(onboarding_step: "verified", participation_status: "completed")
      conversation.update!(status: "completed", question_count: 10)

      allow(Companion::PostDiscoveryRouter).to receive(:call).and_return(conversation)

      handler.handle_inbound_text("thanks!")

      expect(Companion::PostDiscoveryRouter).to have_received(:call).with(
        hash_including(user_message: "thanks!", employee: employee)
      )
      expect(conversation.reload.status).to eq("completed")
    end

    it "still processes active discovery turns via ProcessTurnService" do
      allow(Discovery::ProcessTurnService).to receive(:call).and_return(
        "assistant_message" => "Tell me more.",
        "completed" => false,
        "question_count" => 2
      )

      handler.handle_inbound_text("We use Excel")

      expect(Discovery::ProcessTurnService).to have_received(:call)
      expect(conversation.messages.where(direction: "inbound").last.body).to eq("We use Excel")
    end
  end
end
