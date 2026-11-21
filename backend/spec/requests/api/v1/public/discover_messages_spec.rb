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

  describe "saved discovery recovery" do
    let(:agent) { instance_double(Langgraph::Client) }

    before do
      conversation.update!(status: "profiling", question_count: 0,
                           state_snapshot: { 'discovery_engine_version' => 1, "profiling" => { "step" => "responsibilities" } })
      employee.update!(participation_status: "started", role_title: "HR assistant", department: "hr",
                       seniority: "individual_contributor")
      create(:discovery_playbook, department: "hr")
      allow(Langgraph::Client).to receive(:new).and_return(agent)
      allow(agent).to receive(:create_thread!).and_return("regression-thread")
      allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    end

    it "preserves the exact short profiling answers and retries the kickoff without duplicating a turn" do
      post "/api/v1/public/discover/messages", params: { body: "helping the HR?" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["messages"].last["body"]).to include("Which tools or systems")

      allow(agent).to receive(:run_turn!).and_raise(Langgraph::UnavailableError.new(
        "OpenAI organization spend limit exhausted", retryable: false, code: "openai_quota_exceeded"))
      expect {
        post "/api/v1/public/discover/messages", params: { body: "outlook, Excel and our system" }, headers: headers
      }.not_to have_enqueued_job(RetryDiscoveryTurnJob)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["state"]["discovery_pending"]).to be(true)
      turn = DiscoveryTurn.find_by!(conversation: conversation)
      ProcessDiscoveryTurnJob.perform_now(turn.id)
      get "/api/v1/public/discover/messages", headers: headers
      expect(response.parsed_body["state"]).to include("discovery_pending" => false, "discovery_error" => "openai_quota_exceeded")
      expect(employee.reload.profile_card).to include("responsibilities" => "helping the HR?", "primary_tools" => ["outlook", "Excel", "our system"])
      count = conversation.messages.count

      expect(agent).to receive(:run_turn!).once.with(hash_including(
        user_message: a_string_including("helping the HR?", "outlook, Excel, our system")
      )).and_return("assistant_message" => "Which HR task do you usually start with?", "question_count" => 1, "completed" => false)
      post "/api/v1/public/discover/messages", params: { retry: true }, headers: headers
      expect(response).to have_http_status(:ok)
      ProcessDiscoveryTurnJob.perform_now(turn.id)
      get "/api/v1/public/discover/messages", headers: headers
      expect(response.parsed_body["state"]).to include("question_count" => 1, "discovery_pending" => false, "discovery_error" => nil)
      expect(conversation.messages.count).to eq(count + 1)
      post "/api/v1/public/discover/messages", params: { retry: true }, headers: headers
      expect(response).to have_http_status(:conflict)
      expect(conversation.reload.question_count).to eq(1)
    end


    it "reports active retry work separately from waiting and failed recovery" do
      conversation.update!(status: "discovery")
      source = create(:message, conversation: conversation, direction: "inbound", raw_payload: { "discovery_pending" => true })
      Discovery::TurnStatus.track(source) do
        get "/api/v1/public/discover/messages", headers: headers
        expect(response.parsed_body["state"]).to include("discovery_phase" => "processing", "discovery_pending" => true)
      end
      get "/api/v1/public/discover/messages", headers: headers
      expect(response.parsed_body["state"]["discovery_phase"]).to eq("retry_waiting")
      source.update!(raw_payload: { "discovery_pending" => false, "discovery_error" => "structured_output_truncated" })
      get "/api/v1/public/discover/messages", headers: headers
      expect(response.parsed_body["state"]).to include("discovery_phase" => "failed", "discovery_pending" => false)
    end

    it "rejects another answer while a saved turn is waiting" do
      conversation.update!(status: "discovery")
      create(:message, conversation: conversation, direction: "inbound", raw_payload: { "discovery_pending" => true })
      expect {
        post "/api/v1/public/discover/messages", params: { body: "outlook, Excel and our system" }, headers: headers
      }.not_to change(Message, :count)
      expect(response).to have_http_status(:conflict)
    end
  end

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
    it "distinguishes first admission from retry waiting and returns the source submission identity" do
      conversation.update!(status: 'discovery')
      submission = EmployeeSubmission.create!(conversation: conversation, submission_id: 'ui-stable-id', body: 'Recruitment takes 4–6 hours weekly')
      source = create(:message, conversation: conversation, direction: 'inbound', body: submission.body, employee_submission: submission)
      turn = Discovery::DurableTurn.register(conversation, source, source.body)
      get '/api/v1/public/discover/messages', headers: headers
      expect(response.parsed_body['state']).to include('discovery_phase' => 'queued', 'discovery_pending' => true)
      expect(response.parsed_body['messages'].find { |m| m['id'] == source.id }['submission_id']).to eq('ui-stable-id')
      turn.update!(status: 'processing', attempts: 1, lease_until: 100.seconds.from_now, deadline_at: 85.seconds.from_now)
      get '/api/v1/public/discover/messages', headers: headers
      expect(response.parsed_body['state']['discovery_phase']).to eq('processing')
      turn.update!(status: 'retry_waiting', lease_until: nil, retry_at: 30.seconds.from_now, error_code: 'deadline_exceeded')
      get '/api/v1/public/discover/messages', headers: headers
      expect(response.parsed_body['state']).to include('discovery_phase' => 'retry_waiting', 'discovery_pending' => true)
      expect(conversation.messages.where(direction: 'inbound').count).to eq(1)
    end

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
      allow(Companion::IntentClassifier).to receive(:call).and_return({ intent: "share", confidence: 0.9, source: "llm" })

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
      # source matters now: only a CONFIDENT read may divert an open question to the
      # companion, so the stub has to say where the verdict came from.
      allow(Companion::IntentClassifier).to receive(:call)
        .and_return({ intent: "tools", confidence: 0.9, source: "phrase" })
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
