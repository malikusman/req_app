# frozen_string_literal: true

require "rails_helper"

# One tokenised reply endpoint serves BOTH kinds of ask: an admin-gated clarification
# (ConsultantOutreach) and a direct consultant follow-up question
# (ConsultantInfoRequest). Questions could not be routed through Outreach because
# Outreaches::CreateService always sets pending_admin_approval, which would put a
# company admin in front of every consultant question.
RSpec.describe "Api::V1::Public tokenised reply", type: :request do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }
  let(:employee) { create(:employee, company: company, email: "layla@acme.test", preferred_channel: "web") }
  let!(:conversation) { create(:conversation, employee: employee, company: company, status: "completed") }

  def send_question
    ConsultantFollowup::SendService.call(
      consultant: consultant, employee: employee,
      body: "Which system holds the approval record?", channel: "email"
    )
  end

  describe "a consultant follow-up question" do
    it "resolves the token and shows the question" do
      request = send_question[:request]
      token = request.mint_reply_token!

      get "/api/v1/public/outreach/#{token}"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["outreach"]
      expect(body["body"]).to eq("Which system holds the approval record?")
      expect(body["can_reply"]).to be(true)
    end

    it "accepts an answer and lands it in the employee's thread" do
      request = send_question[:request]
      token = request.mint_reply_token!

      post "/api/v1/public/outreach/#{token}/reply", params: { body: "SAP is the record." }

      expect(response).to have_http_status(:created)
      expect(request.reload.status).to eq("replied")

      answer = conversation.messages.on_track("consultant_followup").where(direction: "inbound").last
      expect(answer.body).to eq("SAP is the record.")
      # Visible where the employee actually converses with us.
      expect(conversation.messages.employee_visible).to include(answer)
    end

    it "advances the consultant's requirement loop from an emailed answer" do
      result = send_question
      package = DiscoveryPackage.create!(
        conversation: conversation, employee: employee, company: company, version: 1, status: "ready"
      )
      requirement = ConsultantRequirement.create!(
        consultant_user: consultant, discovery_package: package, employee: employee,
        company: company, statement: "Which system is the record?", max_questions: 3
      )
      question = package.discovery_followup_questions.create!(
        consultant_requirement: requirement, body: "Which system?", status: "sent",
        queue_position: 1, consultant_info_request: result[:request]
      )
      allow_any_instance_of(Langgraph::Client)
        .to receive(:evaluate_requirement!).and_return({ "satisfied" => true, "missing_aspects" => [] })
      token = result[:request].mint_reply_token!

      post "/api/v1/public/outreach/#{token}/reply", params: { body: "SAP is the record." }

      expect(question.reload.status).to eq("answered")
      expect(requirement.reload).to be_satisfied
    end

    it "rejects a blank answer" do
      token = send_question[:request].mint_reply_token!

      post "/api/v1/public/outreach/#{token}/reply", params: { body: "  " }

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
    end

    it "refuses once the request is closed" do
      request = send_question[:request]
      token = request.mint_reply_token!
      request.update!(status: "closed")

      post "/api/v1/public/outreach/#{token}/reply", params: { body: "too late" }

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
    end
  end

  describe "a clarification outreach still works" do
    let!(:outreach) do
      ConsultantOutreach.create!(
        company: company, consultant_user: consultant, employee: employee, conversation: conversation,
        recipient_type: "employee", purpose: "clarification", channel: "email",
        status: "sent", body: "Could you confirm the approval threshold?", sent_at: Time.current
      )
    end

    it "resolves and accepts a reply on the same endpoint" do
      token = outreach.mint_reply_token!

      post "/api/v1/public/outreach/#{token}/reply", params: { body: "It is 5,000." }

      expect(response).to have_http_status(:created)
      expect(outreach.reload.status).to eq("replied")
      expect(outreach.consultant_outreach_replies.count).to eq(1)
    end
  end

  describe "bad tokens" do
    it "404s an unknown token" do
      get "/api/v1/public/outreach/not-a-real-token"

      expect(response).to have_http_status(:not_found)
    end

    it "404s a token that was replaced by a later mint" do
      request = send_question[:request]
      stale = request.mint_reply_token!
      request.mint_reply_token!

      get "/api/v1/public/outreach/#{stale}"

      expect(response).to have_http_status(:not_found)
    end
  end
end
