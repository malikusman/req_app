# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reviewer report workspace", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:reviewer) { create(:reviewer_user) }
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
  let!(:review) { create(:report_review, report: report, reviewer_user: reviewer, company: company) }

  before do
    create(:reviewer_assignment, company: company, reviewer_user: reviewer)
    report.update!(
      report_snapshot: report.report_snapshot.merge(
        "executive_summary" => "One employee completed discovery.",
        "participation" => { "invited" => 1, "completed" => 1 }
      )
    )
    conversation
  end

  it "returns bundled report, review, and conversation evidence" do
    get "/api/v1/reviewer/companies/#{company.id}/reports/#{report.id}/workspace",
        headers: auth_headers_for(reviewer)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["report"]["id"]).to eq(report.id)
    expect(body["review"]["id"]).to eq(review.id)
    expect(body["conversations"].length).to eq(1)
    expect(body["conversations"].first["messages"].length).to be >= 2
    expect(body["conversations"].first["discovery_state"]["shared_findings"].length).to eq(1)
    expect(body["conversations"].first["discovery_provenance"].length).to eq(1)
  end
end
