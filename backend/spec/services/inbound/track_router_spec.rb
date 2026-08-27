# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inbound::TrackRouter do
  let(:company) { create(:company) }
  let(:employee) do
    create(:employee, company: company, onboarding_step: "verified", participation_status: "completed")
  end
  let(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed", question_count: 6)
  end
  let(:consultant) { create(:consultant_user) }
  let(:client) { Web::CapturingMetaClient.new }

  def open_info_request(body: "Which system holds the approval record?")
    ConsultantInfoRequest.create!(
      company: company,
      consultant_user: consultant,
      employee: employee,
      conversation: conversation,
      body: body,
      status: "awaiting_reply",
      sent_at: Time.current
    )
  end

  describe "with an open consultant question" do
    it "routes a substantive reply to the consultant follow-up track" do
      request = open_info_request
      allow(Companion::IntentClassifier).to receive(:call).and_return({ intent: "share", confidence: 0.9 })

      track = described_class.call(
        employee: employee,
        conversation: conversation,
        text: "It sits in SAP, and finance signs it off manually.",
        channel: "web",
        client: client
      )

      expect(track).to eq(:consultant_followup)
      expect(request.reload.status).to eq("replied")

      message = conversation.messages.on_track("consultant_followup").where(direction: "inbound").last
      expect(message.track_ref).to eq(request)
    end

    it "answers as companion when the message is plainly about something else" do
      request = open_info_request
      allow(Companion::IntentClassifier).to receive(:call).and_return({ intent: "tools", confidence: 0.9 })

      described_class.call(
        employee: employee,
        conversation: conversation,
        text: "any tools you'd recommend for invoice matching?",
        channel: "web",
        client: client
      )

      # The question stays open — a companion aside must not consume it.
      expect(request.reload.status).to eq("awaiting_reply")
      expect(conversation.messages.on_track("consultant_followup").where(direction: "inbound")).to be_empty
    end

    it "treats the message as the answer when intent classification fails" do
      request = open_info_request
      allow(Companion::IntentClassifier).to receive(:call).and_raise(StandardError, "boom")

      track = described_class.call(
        employee: employee,
        conversation: conversation,
        text: "SAP, then a manual sign-off.",
        channel: "web",
        client: client
      )

      expect(track).to eq(:consultant_followup)
      expect(request.reload.status).to eq("replied")
    end

    it "does not consult the classifier while discovery is still running" do
      conversation.update!(status: "discovery")
      request = open_info_request
      expect(Companion::IntentClassifier).not_to receive(:call)

      track = described_class.call(
        employee: employee,
        conversation: conversation,
        text: "SAP holds it.",
        channel: "web",
        client: client
      )

      expect(track).to eq(:consultant_followup)
      expect(request.reload.status).to eq("replied")
    end
  end

  describe "with no open consultant question" do
    it "routes to discovery while the interview is running" do
      conversation.update!(status: "discovery")
      allow(Discovery::ProcessTurnService).to receive(:call).and_return({ "assistant_message" => "ok" })
      allow(Discovery::DeliverReply).to receive(:call)

      track = described_class.call(
        employee: employee,
        conversation: conversation,
        text: "We match invoices in SAP.",
        channel: "web",
        client: client
      )

      expect(track).to eq(:discovery)
      expect(Discovery::ProcessTurnService).to have_received(:call)
    end

    it "routes to companion once the interview is complete" do
      allow(Companion::PostDiscoveryRouter).to receive(:call)

      track = described_class.call(
        employee: employee,
        conversation: conversation,
        text: "one more thing about approvals",
        channel: "web",
        client: client
      )

      expect(track).to eq(:companion)
      expect(Companion::PostDiscoveryRouter).to have_received(:call)
    end

    it "routes to profiling while the profile is being built" do
      conversation.update!(status: "profiling")
      handler = instance_double(Whatsapp::ProfilingHandler, handle_inbound_text: nil)
      allow(Whatsapp::ProfilingHandler).to receive(:new).and_return(handler)

      track = described_class.call(
        employee: employee,
        conversation: conversation,
        text: "I'm an AP clerk",
        channel: "web",
        client: client
      )

      expect(track).to eq(:profiling)
      expect(handler).to have_received(:handle_inbound_text)
    end
  end

  describe "channel attribution between the two ask channels" do
    it "prefers whichever consultant request opened most recently" do
      older = open_info_request(body: "older question")
      older.update!(created_at: 2.days.ago)

      outreach = ConsultantOutreach.create!(
        company: company,
        consultant_user: consultant,
        employee: employee,
        conversation: conversation,
        recipient_type: "employee",
        purpose: "clarification",
        channel: "whatsapp",
        status: "sent",
        body: "newer question",
        sent_at: Time.current
      )
      allow(Companion::IntentClassifier).to receive(:call).and_return({ intent: "share", confidence: 0.9 })

      described_class.call(
        employee: employee,
        conversation: conversation,
        text: "answering the newer one",
        channel: "web",
        client: client
      )

      expect(conversation.messages.on_track("consultant_followup").last.track_ref).to eq(outreach)
      expect(older.reload.status).to eq("awaiting_reply")
    end
  end
end
