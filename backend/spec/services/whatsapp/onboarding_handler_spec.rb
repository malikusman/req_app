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
    before do
      ConsentTextVersion.create!(
        version: "2026-06-20",
        locale: "en",
        active: true,
        confirmation_keywords: %w[YES],
        body: "Reply YES to continue."
      )
    end

    it "prompts for name on first message instead of saving it immediately" do
      handler.handle_inbound_text("Hi")

      employee.reload
      conversation.reload
      expect(employee.display_name).to be_nil
      expect(employee.onboarding_step).to eq("awaiting_name")
      expect(conversation.state_snapshot["onboarding_name_prompt_sent"]).to eq(true)
      expect(conversation.messages.where(direction: "outbound").last.body).to include("What's your name?")
    end

    it "saves the name on the second message and prompts consent" do
      handler.handle_inbound_text("Hi")
      handler.handle_inbound_text("Sam Tester")

      employee.reload
      expect(employee.display_name).to eq("Sam Tester")
      expect(employee.onboarding_step).to eq("awaiting_consent")
      expect(conversation.messages.where(direction: "outbound").last.body).to include("YES")
    end
  end

  describe "awaiting_consent when name was set at invite" do
    let(:employee) do
      create(:employee,
             company: company,
             phone_e164: "+14155550100",
             display_name: "Sam Tester",
             participation_status: "invited",
             onboarding_step: "awaiting_consent",
             invited_at: Time.current,
             verified_at: Time.current)
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

    it "sends consent when the first message is not YES" do
      handler.handle_inbound_text("Hi")

      employee.reload
      expect(employee.onboarding_step).to eq("awaiting_consent")
      expect(conversation.messages.where(direction: "outbound").last.body).to include("YES")
    end

    # Consent required the WHOLE message to equal a keyword, so a person
    # answering a question the way people answer questions was refused — twice,
    # with the same instruction — at the very first step of the product.
    describe "what counts as a yes" do
      # The consent text has already gone out; this is the reply to it.
      before do
        conversation.messages.create!(direction: "outbound", channel: "whatsapp",
                                      message_type: "text", body: "Reply YES to continue.")
      end

      def consent_after(reply)
        described_class.new(employee: employee, conversation: conversation, client: client)
                       .handle_inbound_text(reply)
        employee.reload.consent_given_at.present?
      end

      [
        "YES",
        "yes",
        "Yes.",
        "Yes, happy to take part",
        "yes please",
        "Yeah sure, go ahead",
        "OK, let's do it",
        "I agree to the above",
        "Sure thing",
        "Happy to help with this"
      ].each do |reply|
        it "accepts #{reply.inspect}" do
          expect(consent_after(reply)).to be(true)
        end
      end

      # A false re-prompt costs one message. A false consent is not recoverable,
      # so anything carrying a negation is refused even when it opens with a yes.
      [
        "No",
        "No thanks",
        "Not right now",
        "yes but not the recording",
        "OK but I do not consent to being recorded",
        "I would rather not",
        "maybe later",
        "who is this?",
        "Yesterday I was asked the same thing"
      ].each do |reply|
        it "refuses #{reply.inspect}" do
          expect(consent_after(reply)).to be(false)
        end
      end

      it "records which consent text version was agreed to" do
        consent_after("Yes, happy to take part")
        expect(employee.reload.consent_text_version).to eq("2026-06-20")
      end
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
             invited_at: Time.current,
             verified_at: Time.current)
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
