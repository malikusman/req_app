# frozen_string_literal: true

require "rails_helper"

# The key user's conversation with leadership, in the portal (Doc 08).
RSpec.describe "Key user's conversation with leadership", type: :request do
  let(:company) { create(:company, company_profile: { "industry" => "Wholesale distribution" }) }
  let(:user) { create(:company_user, company: company, name: "Layla Haddad", job_title: "CEO") }
  let(:headers) { auth_headers_for(user) }
  let!(:engagement) do
    create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY", key_user: user,
                        planned_departments: [{ "name" => "Sales", "count" => 2 }])
  end
  let(:client) { KeyPersonFakeClient.scripted }
  let(:path) { "/api/v1/company/leadership" }

  before do
    allow(Openai::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    KeyPerson::Kickoff.call(engagement)
  end

  def say(text, id: SecureRandom.uuid)
    post "#{path}/messages", params: { text: text, client_message_id: id }, headers: headers, as: :json
  end

  def own = engagement.participants.find_by!(source: "KEY_USER")

  it "shows the consent note before anything starts" do
    get path, headers: headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["available"]).to be(true)
    expect(body["session"]).to be_nil
    expect(body["consent"]["points"].join).to include("isn't shown to colleagues")
  end

  it "opens once consent is given, then answers each message" do
    post "#{path}/consent", headers: headers
    expect(own.reload).to have_attributes(participation_status: "STARTED", consent_text_version: "2026-11-05")
    session = response.parsed_body["session"]
    expect(session["state"]).to eq("OPENING")
    expect(session["turns"].map { |t| t["from"] }).to eq(%w[assistant])

    say("Yes, let's start.")
    turns = response.parsed_body["session"]["turns"]
    expect(turns.last).to include("from" => "assistant")
    expect(turns.last["text"]).to include("strategic objectives")
  end

  it "runs a whole conversation to completion and hands over to pricing" do
    post "#{path}/consent", headers: headers
    40.times do |i|
      break if response.parsed_body.dig("session", "finished")

      say("Answer number #{i}, with something useful in it.")
    end

    session = own.conversation_sessions.last
    expect(session).to have_attributes(state: "COMPLETE", close_reason: "COVERAGE_COMPLETE")
    expect(session.turns.from_assistant.pluck(:mode).last(4))
      .to eq(%w[PRIORITY_READ_BACK SCOPE_AND_PARTICIPANTS ANYTHING_ELSE CLOSING])
    expect(own.reload.participation_status).to eq("COMPLETED")
    expect(engagement.reload.status).to eq("STAGE_1_PRICING")
    expect(AiRun.where(stage: %w[P02 P03]).count).to be > 20
  end

  it "never shows the participant what was captured or the planner's state" do
    post "#{path}/consent", headers: headers
    say("We want to grow into Saudi.")

    raw = response.body
    %w[capture coverage state_snapshot routing_decision slots_filled summary_update political].each do |key|
      expect(raw).not_to include("\"#{key}\"")
    end
  end

  it "answers the same message once, even if it is sent twice" do
    post "#{path}/consent", headers: headers
    say("We want to grow into Saudi.", id: "m-1")
    say("We want to grow into Saudi.", id: "m-1")

    expect(own.conversation_sessions.last.turns.from_participant.count).to eq(1)
  end

  it "pauses, and welcomes them back on the same thread" do
    post "#{path}/consent", headers: headers
    say("Yes")
    asked = own.conversation_sessions.last.turns.last.targeted_slot

    post "#{path}/pause", headers: headers
    expect(response.parsed_body["session"]).to include("state" => "PAUSED", "needs_resume" => true)

    post "#{path}/resume", headers: headers
    last = own.conversation_sessions.last.turns.last
    expect(last).to have_attributes(mode: "RESUME", targeted_slot: asked)
  end

  it "refuses a message before consent, and after the end" do
    say("Hello")
    expect(response).to have_http_status(:conflict)

    post "#{path}/consent", headers: headers
    own.conversation_sessions.last.update!(state: "COMPLETE")
    say("One more thing")
    expect(response).to have_http_status(:conflict)
  end

  it "is the key user's alone" do
    other = create(:company_user, company: company)
    get path, headers: auth_headers_for(other)
    expect(response).to have_http_status(:forbidden)
  end

  it "says so when the conversation isn't available" do
    allow(Llm::KeyPerson).to receive(:enabled?).and_return(false)
    get path, headers: headers
    expect(response.parsed_body["available"]).to be(false)

    post "#{path}/consent", headers: headers
    expect(response).to have_http_status(:service_unavailable)
  end

  describe "facts learned in conversation (Doc 07 §10)" do
    let(:client) do
      KeyPersonFakeClient.scripted do |capture, _context, turn_id|
        capture.merge("profile_facts_discovered" => [
                        { "field" => "locations", "value" => "UAE, Oman", "contradicts_known" => false, "evidence" => turn_id },
                        { "field" => "industry", "value" => "Retail", "contradicts_known" => true, "evidence" => turn_id }
                      ])
      end
    end

    it "fills a missing fact as DISCOVERED_LATER and never overwrites a confirmed one" do
      post "#{path}/consent", headers: headers
      say("We're in the UAE and Oman, and honestly we're more retail these days.")

      company.reload
      expect(company.company_profile["locations"]).to eq(%w[UAE Oman])
      expect(company.profile_provenance.dig("locations", "source")).to eq("DISCOVERED_LATER")
      expect(company.company_profile["industry"]).to eq("Wholesale distribution")
      expect(own.conversation_sessions.last.state_snapshot["contradictions"].pluck("field")).to eq(["industry"])
    end
  end

  describe "a sensitive matter" do
    let(:consultant) { create(:consultant_user) }
    let(:client) do
      KeyPersonFakeClient.scripted do |capture, _context, turn_id|
        capture.merge("sensitive" => [{ "type" => "RESTRUCTURING", "note" => "Plans to merge two teams.",
                                        "evidence" => turn_id }])
      end
    end

    before { engagement.update!(lead_consultant: consultant) }

    it "flags the session for the lead consultant and carries on" do
      post "#{path}/consent", headers: headers
      say("We're planning to merge sales and customer service next quarter.")

      session = own.conversation_sessions.last
      expect(session.needs_review).to be(true)
      expect(session.review_reasons).to eq([{ "type" => "RESTRUCTURING", "turn" => "t2" }])
      expect(session.state).not_to eq("COMPLETE")
      expect(Notification.where(recipient: consultant, notification_type: "key_person_review").count).to eq(1)
    end
  end
end
