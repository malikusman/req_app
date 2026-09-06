# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant report workspace", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:consultant) { create(:consultant_user) }
  let(:employee) { create(:employee, company: company, display_name: "Sam Tester", department: "finance") }
  let!(:conversation) do
    create(:conversation, employee: employee, company: company, status: "completed", question_count: 3).tap do |conv|
      conv.update!(
        state_snapshot: {
          "last_routing_decision" => { "action" => "close", "agent" => "process", "reason" => "done" },
          "blackboard" => {
            "profile" => { "role_title" => "Analyst", "department" => "finance" },
            "shared_findings" => [{ "agent" => "process", "finding" => "Uses Slack for reviews", "confidence" => 0.8, "turn" => 2 }],
            "conversation_summary" => "Employee described daily workflow.",
            "agent_queue" => [],
            "agent_states" => {},
            "coverage" => { "topics_required" => %w[tools], "topics_covered" => %w[tools] }
          }
        }
      )
      create(:message, conversation: conv, direction: "inbound", body: "We use Slack and Excel daily")
      create(
        :message,
        conversation: conv,
        direction: "outbound",
        body: "What tools do you use?",
        is_discovery_question: true,
        agent_id: "process",
        routing_decision: { "action" => "continue", "agent" => "process", "reason" => "tools topic" }
      )
    end
  end
  let!(:report) { create(:report, :ready, company: company) }
  let!(:review) { create(:report_review, report: report, consultant_user: consultant, company: company) }
  let(:co_consultant) { create(:consultant_user, name: "Co Consultant") }
  let!(:co_review) { create(:report_review, report: report, consultant_user: co_consultant, company: company, status: "pending") }

  before do
    create(:consultant_assignment, company: company, consultant_user: consultant)
    create(:consultant_assignment, company: company, consultant_user: co_consultant)
    report.update!(
      report_snapshot: report.report_snapshot.merge(
        "executive_summary" => "One employee completed discovery.",
        "participation" => { "invited" => 1, "completed" => 1 }
      )
    )
    conversation
  end

  it "returns bundled report, review, and conversation evidence" do
    get "/api/v1/consultant/companies/#{company.id}/reports/#{report.id}/workspace",
        headers: auth_headers_for(consultant)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["report"]["id"]).to eq(report.id)
    expect(body["review"]["id"]).to eq(review.id)
    expect(body["conversations"].length).to eq(1)
    expect(body["conversations"].first["messages"].length).to be >= 2
    expect(body["conversations"].first["discovery_state"]["shared_findings"].length).to eq(1)
    expect(body["conversations"].first["discovery_provenance"].length).to eq(1)
  end

  it "includes co-consultant activity when they have chatted" do
    create(:consultant_chat_message, company: company, sender_consultant_user: co_consultant, body: "Hello from co-consultant")

    get "/api/v1/consultant/companies/#{company.id}/reports/#{report.id}/workspace",
        headers: auth_headers_for(consultant)

    co_payload = JSON.parse(response.body)["co_consultant_reviews"].first
    expect(co_payload["activity"]).to eq("discussing")
    expect(co_payload["chat_message_count"]).to eq(1)
    expect(co_payload["activity_detail"]).to include("1 chat message")
  end
end
