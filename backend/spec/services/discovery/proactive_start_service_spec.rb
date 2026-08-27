# frozen_string_literal: true

require "rails_helper"

RSpec.describe Discovery::ProactiveStartService do
  let(:company) { create(:company, settings: { "discovery_multi_agent_enabled" => false }) }
  let(:employee) do
    create(:employee, company: company, display_name: "Sam", onboarding_step: "verified",
                      role_title: "Analyst", department: "finance", seniority: "individual_contributor",
                      metadata: { "profile" => { "responsibilities" => "Reporting", "primary_tools" => ["Excel"] } })
  end
  let(:conversation) { create(:conversation, employee: employee, status: "discovery", question_count: 0) }
  let(:meta_client) { instance_double(Whatsapp::MetaClient, configured?: false) }

  before { create(:discovery_playbook, department: "finance") }

  describe ".call" do
    it "persists a system kickoff, runs the first turn, and delivers the reply" do
      allow(meta_client).to receive(:send_typing_on)
      allow(Discovery::ProcessTurnService).to receive(:call).and_return(
        { "assistant_message" => "Thanks Sam — what does a typical morning look like?", "completed" => false,
          "question_count" => 1 }
      )

      described_class.call(conversation: conversation, employee: employee, client: meta_client,
                           trigger_message_id: "wamid.test")

      kickoff = conversation.messages.find_by(message_type: "system")
      expect(kickoff).to be_present
      expect(kickoff.direction).to eq("inbound")
      expect(kickoff.raw_payload["kind"]).to eq("discovery_kickoff")
      expect(kickoff.body).to include("Sam")
      expect(kickoff.body).to include("Analyst")

      expect(Discovery::ProcessTurnService).to have_received(:call).with(
        hash_including(
          conversation: conversation,
          employee: employee,
          user_message: kickoff.body,
          inbound_message: kickoff
        )
      )

      outbound = conversation.messages.where(direction: "outbound").last
      expect(outbound.body).to include("typical morning")
    end

    it "shows a typing indicator when a trigger message id is provided" do
      allow(meta_client).to receive(:send_typing_on)
      allow(Discovery::ProcessTurnService).to receive(:call).and_return(
        { "assistant_message" => "First question?", "completed" => false, "question_count" => 1 }
      )

      described_class.call(conversation: conversation, employee: employee, client: meta_client,
                           trigger_message_id: "wamid.consent")

      expect(meta_client).to have_received(:send_typing_on).with(message_id: "wamid.consent")
    end

    # There is no agent queue to build any more: the interview discovers the
    # person's own role areas on its first turns. What kickoff must still do is
    # seed the profile the orientation phase builds on.
    it "seeds the profile onto the blackboard for the interview to start from" do
      company.update!(settings: company.settings.merge("discovery_multi_agent_enabled" => true))
      allow(Discovery::ProcessTurnService).to receive(:call).and_return(
        { "assistant_message" => "Q", "completed" => false, "question_count" => 1 }
      )

      described_class.call(conversation: conversation, employee: employee, client: meta_client)

      expect(conversation.reload.blackboard["profile"]).to be_present
    end
  end
end

RSpec.describe Discovery::KickoffMessage do
  it "builds a profile summary when profiling is complete" do
    employee = build(:employee,
                     display_name: "Sam",
                     role_title: "AP Specialist",
                     department: "finance",
                     seniority: "individual_contributor",
                     metadata: {
                       "profile" => {
                         "responsibilities" => "Invoice processing",
                         "primary_tools" => %w[SAP Excel]
                       }
                     })

    body = described_class.build(employee: employee)
    expect(body).to include("Sam")
    expect(body).to include("AP Specialist")
    expect(body).to include("Invoice processing")
    expect(body).to include("SAP")
  end

  it "builds a minimal intro when profiling is incomplete" do
    employee = build(:employee, display_name: "Sam", role_title: nil, department: nil)

    body = described_class.build(employee: employee)
    expect(body).to include("Sam")
    expect(body).to include("ready to walk through")
  end
end
