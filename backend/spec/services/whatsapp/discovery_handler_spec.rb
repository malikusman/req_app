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
end
