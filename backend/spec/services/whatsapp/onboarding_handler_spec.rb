# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::OnboardingHandler do
  let(:company) { create(:company, settings: { "discovery_profiling_enabled" => true }) }
  let(:employee) do
    create(:employee,
           company: company,
           phone_e164: "+14155550100",
           display_name: nil,
           participation_status: "invited",
           onboarding_step: "awaiting_name",
           invited_at: Time.current)
  end
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "onboarding") }
  let(:client) { instance_double(Whatsapp::MetaClient, configured?: false) }
  let(:handler) { described_class.new(employee: employee, conversation: conversation, client: client) }

  describe "awaiting_name" do
    it "prompts for name on first message instead of saving it immediately" do
      handler.handle_inbound_text("Hi")

      employee.reload
      conversation.reload
      expect(employee.display_name).to be_nil
      expect(employee.onboarding_step).to eq("awaiting_name")
      expect(conversation.state_snapshot["onboarding_name_prompt_sent"]).to eq(true)
      expect(conversation.messages.where(direction: "outbound").last.body).to include("What's your name?")
    end

    it "saves the name on the second message" do
      handler.handle_inbound_text("Hi")
      handler.handle_inbound_text("Sam Tester")

      employee.reload
      expect(employee.display_name).to eq("Sam Tester")
      expect(employee.onboarding_step).to eq("awaiting_access_code")
    end
  end

  describe "awaiting_access_code" do
    let(:employee) do
      create(:employee,
             company: company,
             phone_e164: "+14155550100",
             display_name: "Sam Tester",
             participation_status: "invited",
             onboarding_step: "awaiting_access_code",
             invited_at: Time.current)
    end
    let(:plain_code) do
      _record, plain = EmployeeAccessCode.issue_for!(employee: employee, issued_by_type: "system")
      plain
    end

    before do
      ConsentTextVersion.create!(
        version: "2026-06-20",
        locale: "en",
        active: true,
        confirmation_keywords: %w[YES],
        body: "Reply YES to continue."
      )
      allow(Subscriptions::ConversationLimitEnforcer).to receive(:can_start_discovery?).and_return(true)
      allow(Subscriptions::ConversationLimitEnforcer).to receive(:record_discovery_started!)
    end

    it "accepts the access code as the first message when name was set at invite" do
      handler.handle_inbound_text(plain_code)

      employee.reload
      expect(employee.onboarding_step).to eq("awaiting_consent")
    end
  end

  describe "awaiting_consent without profiling" do
    let(:company) { create(:company, settings: { "discovery_profiling_enabled" => false }) }
    let(:employee) do
      create(:employee,
             company: company,
             phone_e164: "+14155550100",
             display_name: "Sam Tester",
             participation_status: "invited",
             onboarding_step: "awaiting_consent",
             invited_at: Time.current)
    end
    let(:plain_code) do
      _record, plain = EmployeeAccessCode.issue_for!(employee: employee, issued_by_type: "system")
      plain
    end

    before do
      ConsentTextVersion.create!(
        version: "2026-06-20",
        locale: "en",
        active: true,
        confirmation_keywords: %w[YES],
        body: "Reply YES to continue."
      )
      create(:discovery_playbook, department: "default")
      allow(Subscriptions::ConversationLimitEnforcer).to receive(:can_start_discovery?).and_return(true)
      allow(Subscriptions::ConversationLimitEnforcer).to receive(:record_discovery_started!)
      allow(Discovery::ProactiveStartService).to receive(:call)
    end

    it "starts discovery proactively after consent" do
      handler.handle_inbound_text(plain_code)
      handler.handle_inbound_text("YES", external_id: "wamid.consent")

      employee.reload
      conversation.reload
      expect(employee.onboarding_step).to eq("verified")
      expect(conversation.status).to eq("discovery")
      expect(Discovery::ProactiveStartService).to have_received(:call).with(
        hash_including(
          conversation: conversation,
          employee: employee,
          trigger_message_id: "wamid.consent"
        )
      )
    end
  end
end
