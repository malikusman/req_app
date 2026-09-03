# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discovery::DeliverReply do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "discovery") }

  describe "a delayed (retry-placeholder) result" do
    it "tags the persisted message so it can be excluded from model history" do
      message = described_class.call(
        conversation: conversation, employee: employee,
        result: { "delayed" => true, "assistant_message" => "We're experiencing a brief delay — we'll pick up right where we left off shortly." },
        channel: :web
      )

      expect(message.raw_payload["kind"]).to eq("delay_notice")
    end

    it "still shows the apology to the employee (message_type stays text)" do
      message = described_class.call(
        conversation: conversation, employee: employee,
        result: { "delayed" => true, "assistant_message" => "brief delay" },
        channel: :web
      )

      expect(message.message_type).to eq("text")
      expect(message.track).not_to eq("system")
    end
  end

  describe "a real turn result" do
    it "does not tag an ordinary discovery question" do
      conversation.update!(question_count: 1)
      message = described_class.call(
        conversation: conversation, employee: employee,
        result: { "delayed" => false, "completed" => false, "assistant_message" => "What tools do you use?" },
        channel: :web
      )

      expect(message.raw_payload["kind"]).to be_nil
    end
  end
end
