# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discovery::AdmitSubmission do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "discovery") }

  before do
    allow(Web::TurnRouter).to receive(:handle_text) do |conversation:, text:, **|
      create(:message, conversation: conversation, direction: "inbound", channel: "web", track: "discovery", body: text)
    end
  end

  it "accepts only the voice flags from request params" do
    expect(described_class.input_meta(ActionController::Parameters.new(input_mode: "voice", interrupted_question: "true", other: 1)))
      .to eq("input_mode" => "voice", "interrupted_question" => true)
    expect(described_class.input_meta(ActionController::Parameters.new(input_mode: "voice"))).to eq("input_mode" => "voice", "interrupted_question" => false)
    expect(described_class.input_meta(ActionController::Parameters.new(input_mode: "telepathy"))).to eq({})
  end

  it "marks the saved answer as spoken, and leaves typed answers unmarked" do
    described_class.call(conversation: conversation, employee: employee, submission_id: "s-1", body: "I run payroll",
                         input_meta: { "input_mode" => "voice", "interrupted_question" => true })
    spoken = conversation.messages.where(direction: "inbound").last
    expect(spoken.raw_payload).to include("input_mode" => "voice", "interrupted_question" => true)
  end

  it "does not mark a typed answer" do
    described_class.call(conversation: conversation, employee: employee, submission_id: "s-2", body: "I run payroll")
    expect(conversation.messages.where(direction: "inbound").last.raw_payload.to_h).not_to have_key("input_mode")
  end
end
