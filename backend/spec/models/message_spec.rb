# frozen_string_literal: true

require "rails_helper"

RSpec.describe Message do
  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }

  describe "track derivation" do
    it "keeps an explicitly supplied track" do
      conversation = create(:conversation, employee: employee, company: company, status: "discovery")
      message = create(:message, conversation: conversation, track: "companion")

      expect(message.track).to eq("companion")
    end

    it "labels a system message as system regardless of conversation state" do
      conversation = create(:conversation, employee: employee, company: company, status: "discovery")
      message = create(:message, conversation: conversation, message_type: "system")

      expect(message.track).to eq("system")
    end

    it "labels a consultant follow-up from the legacy boolean" do
      conversation = create(:conversation, employee: employee, company: company, status: "completed")
      message = create(:message, conversation: conversation, reviewer_followup: true)

      expect(message.track).to eq("consultant_followup")
    end

    it "labels a companion turn from its agent_id" do
      conversation = create(:conversation, employee: employee, company: company, status: "completed")
      message = create(:message, conversation: conversation, agent_id: "companion")

      expect(message.track).to eq("companion")
    end

    it "labels a companion turn from its routing decision action" do
      conversation = create(:conversation, employee: employee, company: company, status: "completed")
      message = create(
        :message,
        conversation: conversation,
        routing_decision: { "action" => "companion_tools", "agent" => "companion" }
      )

      expect(message.track).to eq("companion")
    end

    it "follows the conversation status while onboarding or profiling" do
      conversation = create(:conversation, employee: employee, company: company, status: "profiling")
      message = create(:message, conversation: conversation)

      expect(message.track).to eq("profiling")
    end

    it "falls back to discovery" do
      conversation = create(:conversation, employee: employee, company: company, status: "discovery")
      message = create(:message, conversation: conversation)

      expect(message.track).to eq("discovery")
    end

    it "rejects an unknown track" do
      conversation = create(:conversation, employee: employee, company: company)

      expect { create(:message, conversation: conversation, track: "nonsense") }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "legacy boolean sync" do
    let(:conversation) { create(:conversation, employee: employee, company: company, status: "completed") }

    it "sets reviewer_followup when the track is consultant_followup" do
      message = create(:message, conversation: conversation, track: "consultant_followup")

      expect(message.reviewer_followup).to be(true)
      expect(described_class.reviewer_followup_only).to include(message)
    end

    it "clears reviewer_followup for every other track" do
      message = create(:message, conversation: conversation, track: "companion", reviewer_followup: true)

      expect(message.reviewer_followup).to be(false)
      expect(described_class.discovery_only).to include(message)
    end
  end

  describe "scopes" do
    let(:conversation) { create(:conversation, employee: employee, company: company, status: "completed") }

    it "employee_visible excludes only system plumbing" do
      discovery = create(:message, conversation: conversation, track: "discovery")
      companion = create(:message, conversation: conversation, track: "companion")
      followup = create(:message, conversation: conversation, track: "consultant_followup")
      system = create(:message, conversation: conversation, message_type: "system")

      visible = conversation.messages.employee_visible

      expect(visible).to include(discovery, companion, followup)
      expect(visible).not_to include(system)
    end

    it "on_track filters to the named tracks" do
      companion = create(:message, conversation: conversation, track: "companion")
      create(:message, conversation: conversation, track: "discovery")

      expect(conversation.messages.on_track("companion")).to contain_exactly(companion)
    end
  end

  describe "track_ref" do
    it "attributes a message to the request that prompted it" do
      conversation = create(:conversation, employee: employee, company: company, status: "completed")
      reviewer = create(:reviewer_user)
      request = ReviewerInfoRequest.create!(
        company: company,
        reviewer_user: reviewer,
        employee: employee,
        conversation: conversation,
        body: "Which system holds the approval record?",
        status: "awaiting_reply"
      )

      message = create(
        :message,
        conversation: conversation,
        track: "consultant_followup",
        track_ref: request
      )

      expect(message.reload.track_ref).to eq(request)
    end
  end
end
