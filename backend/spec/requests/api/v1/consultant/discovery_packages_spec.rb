# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Consultant::DiscoveryPackages", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:employee) { create(:employee, company: company) }
  let(:consultant) { create(:consultant_user) }
  let!(:assignment) { create(:consultant_assignment, consultant_user: consultant, company: company) }
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "completed") }
  let(:package) do
    DiscoveryPackage.create!(
      conversation: conversation, employee: employee, company: company,
      version: 1, status: "ready",
      recommendation: "Automate matching.", agent_payload: { "recommendation" => "Automate matching." }
    )
  end
  let!(:agent_issue) do
    package.discovery_package_items.create!(
      kind: "issue", title: "Copy-paste", body: "Manual copy-paste", origin: "agent", status: "proposed"
    )
  end
  let(:headers) do
    token = JsonWebToken.encode(
      { sub: "consultant_user:#{consultant.id}", aud: "consultant", role: "consultant", jti: consultant.jti }
    )
    { "Authorization" => "Bearer #{token}" }
  end

  def path(suffix = "")
    "/api/v1/consultant/discovery_packages/#{package.id}#{suffix}"
  end

  describe "amending the package" do
    it "lets the consultant rewrite the recommendation, keeping the agent's original" do
      patch path, params: { recommendation: "Start with approvals instead." }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(package.reload.recommendation).to eq("Start with approvals instead.")
      # The agent's original is preserved for audit — an edit is never destructive.
      expect(package.agent_payload["recommendation"]).to eq("Automate matching.")
    end

    it "marks an agent item amended when its text is edited" do
      patch path("/items/#{agent_issue.id}"), params: { body: "Reworded by the consultant" }, headers: headers

      expect(agent_issue.reload.status).to eq("amended")
      expect(agent_issue.body).to eq("Reworded by the consultant")
    end

    it "keeps an explicit rejection even when the body is edited too" do
      patch path("/items/#{agent_issue.id}"),
            params: { body: "still wrong", status: "rejected" }, headers: headers

      expect(agent_issue.reload.status).to eq("rejected")
    end

    it "records a consultant's own issue as theirs" do
      post path("/items"), params: { kind: "issue", body: "Something the agent missed" }, headers: headers

      expect(response).to have_http_status(:created)
      item = package.discovery_package_items.order(:id).last
      expect(item.origin).to eq("consultant")
      expect(item.status).to eq("accepted")
    end
  end

  describe "stating a need" do
    before do
      allow_any_instance_of(Langgraph::Client).to receive(:draft_requirement_questions!).and_return(
        { "questions" => [{ "body" => "Which system holds the approval?", "rationale" => "Settles it" }] }
      )
    end

    it "creates the requirement and returns the drafted questions" do
      post path("/requirements"),
           params: { statement: "I need to know the system of record for approvals." },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)["requirement"]
      expect(body["statement"]).to include("system of record")
      # Drafting runs off the request path, so the response returns the recorded
      # need and the questions follow.
      expect(body["question_ids"]).to eq([])
      expect(body["budget_remaining"]).to eq(3)

      perform_enqueued_jobs
      expect(ConsultantRequirement.last.discovery_followup_questions.count).to eq(1)
    end

    it "rejects a blank statement" do
      post path("/requirements"), params: { statement: "   " }, headers: headers

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
    end

    it "lets the consultant close their own need by hand" do
      post path("/requirements"), params: { statement: "Need the owner." }, headers: headers
      requirement = ConsultantRequirement.last

      patch path("/requirements/#{requirement.id}"), params: { status: "satisfied" }, headers: headers

      expect(requirement.reload).to be_satisfied
      # The consultant is the authority, whatever the agent judged.
      expect(requirement.satisfaction_basis).to eq("consultant_manual")
    end

    it "supersedes drafted questions when a need is withdrawn" do
      post path("/requirements"), params: { statement: "Never mind." }, headers: headers
      perform_enqueued_jobs
      requirement = ConsultantRequirement.last

      patch path("/requirements/#{requirement.id}"), params: { status: "withdrawn" }, headers: headers

      expect(requirement.reload.status).to eq("withdrawn")
      expect(requirement.discovery_followup_questions.pluck(:status)).to all(eq("superseded"))
    end
  end

  describe "the drafted question queue" do
    let!(:question) do
      package.discovery_followup_questions.create!(body: "Which system?", status: "drafted", queue_position: 1)
    end

    it "lets the consultant reorder and skip, but not rewrite" do
      patch path("/followup_questions/#{question.id}"),
            params: { queue_position: 5, status: "skipped", body: "my own wording" },
            headers: headers

      expect(question.reload.queue_position).to eq(5)
      expect(question.status).to eq("skipped")
      # Question text is the agent's to write, not the consultant's.
      expect(question.body).to eq("Which system?")
    end

    it "refuses to change a question that has already gone out" do
      question.update!(status: "sent")

      patch path("/followup_questions/#{question.id}"), params: { queue_position: 2 }, headers: headers

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
    end
  end

  describe "authorization" do
    it "hides a package for a company the consultant is not assigned to" do
      other = create(:company)
      other_conversation = create(:conversation, employee: create(:employee, company: other), company: other)
      other_package = DiscoveryPackage.create!(
        conversation: other_conversation, employee: other_conversation.employee,
        company: other, version: 1, status: "ready"
      )

      patch "/api/v1/consultant/discovery_packages/#{other_package.id}",
            params: { recommendation: "nope" }, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "rejects an unauthenticated request" do
      patch path, params: { recommendation: "nope" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
