# frozen_string_literal: true

require "rails_helper"

# Regression cover for the two web-channel gaps that made a consultant's question
# unanswerable on the employee's own thread:
#
#   1. Web::TurnRouter never checked for an open consultant request, so a reply was
#      swallowed by the discovery handler and the consultant was never notified.
#   2. visible_messages filtered through `discovery_only` (consultant_followup: false),
#      so the consultant's question was invisible in the thread meant to answer it.
RSpec.describe "Api::V1::Public::DiscoverMessages", type: :request do
  let(:company) { create(:company) }
  let(:employee) do
    create(:employee, company: company, onboarding_step: "verified", participation_status: "completed")
  end
  let!(:session) do
    create(:employee_web_session, employee: employee, company: company, verified_at: Time.current)
  end
  let(:headers) { employee_web_headers(session: session, employee: employee) }
  let!(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed", question_count: 6)
  end
  let(:consultant) { create(:consultant_user) }

  def consultant_question!(body: "Which system holds the approval record?")
    request = ConsultantInfoRequest.create!(
      company: company,
      consultant_user: consultant,
      employee: employee,
      conversation: conversation,
      body: body,
      status: "awaiting_reply",
      sent_at: Time.current
    )
    create(
      :message,
      conversation: conversation,
      direction: "outbound",
      body: body,
      track: "consultant_followup",
      track_ref: request
    )
    request
  end

  describe "GET /api/v1/public/discover/messages" do
    it "shows the consultant's question in the employee thread" do
      consultant_question!(body: "Which system holds the approval record?")

      get "/api/v1/public/discover/messages", headers: headers

      expect(response).to have_http_status(:ok)
      bodies = JSON.parse(response.body)["messages"].map { |m| m["body"] }
      expect(bodies).to include("Which system holds the approval record?")
    end

    it "labels each message with its track so the client can attribute it" do
      consultant_question!
      create(:message, conversation: conversation, body: "earlier answer", track: "discovery")

      get "/api/v1/public/discover/messages", headers: headers

      tracks = JSON.parse(response.body)["messages"].map { |m| m["track"] }
      expect(tracks).to include("consultant_followup", "discovery")
    end

    it "still hides system plumbing" do
      create(:message, conversation: conversation, message_type: "system", body: "internal note")

      get "/api/v1/public/discover/messages", headers: headers

      bodies = JSON.parse(response.body)["messages"].map { |m| m["body"] }
      expect(bodies).not_to include("internal note")
    end
  end

  describe "POST /api/v1/public/discover/messages" do
    it "routes a reply to the open consultant question rather than the companion" do
      request = consultant_question!
      allow(Companion::IntentClassifier).to receive(:call).and_return({ intent: "share", confidence: 0.9 })

      post "/api/v1/public/discover/messages",
           params: { body: "It sits in SAP and finance signs it off by hand." },
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(request.reload.status).to eq("replied")
      expect(request.consultant_info_replies.count).to eq(1)

      inbound = conversation.messages.on_track("consultant_followup").where(direction: "inbound").last
      expect(inbound.body).to eq("It sits in SAP and finance signs it off by hand.")
      expect(inbound.track_ref).to eq(request)
    end

    it "leaves the question open when the employee asks about something else" do
      request = consultant_question!
      allow(Companion::IntentClassifier).to receive(:call).and_return({ intent: "tools", confidence: 0.9 })
      allow(Companion::PostDiscoveryRouter).to receive(:call)

      post "/api/v1/public/discover/messages",
           params: { body: "any tools for invoice matching?" },
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(request.reload.status).to eq("awaiting_reply")
      expect(Companion::PostDiscoveryRouter).to have_received(:call)
    end
  end
end
