# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reviewer report discussions", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:reviewer) { create(:reviewer_user) }
  let(:co_reviewer) { create(:reviewer_user, name: "Co Reviewer") }
  let!(:report) { create(:report, :ready, company: company) }
  let!(:review) { create(:report_review, report: report, reviewer_user: reviewer, company: company) }
  let!(:co_review) { create(:report_review, report: report, reviewer_user: co_reviewer, company: company) }
  let(:employee) { create(:employee, company: company) }
  let!(:conversation) { create(:conversation, employee: employee, company: company) }
  let!(:message) { create(:message, conversation: conversation, direction: "inbound", body: "We use Slack") }

  before do
    create(:reviewer_assignment, company: company, reviewer_user: reviewer)
    create(:reviewer_assignment, company: company, reviewer_user: co_reviewer)
  end

  it "creates a co-reviewer discussion on a message anchor" do
    expect do
      post "/api/v1/reviewer/companies/#{company.id}/reports/#{report.id}/discussions",
           params: {
             target_type: "reviewer",
             target_reviewer_user_id: co_reviewer.id,
             anchor_type: "message",
             anchor_id: message.id,
             body: "Does this match your read?"
           },
           headers: auth_headers_for(reviewer)
    end.to change(ReviewDiscussion, :count).by(1)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["discussion"]["anchor_type"]).to eq("message")
    expect(body["discussion"]["target_type"]).to eq("reviewer")
  end

  it "includes discussions in workspace payload" do
    create(
      :review_discussion,
      report: report,
      company: company,
      author_reviewer_user: reviewer,
      target_reviewer_user: co_reviewer,
      anchor_type: "message",
      anchor_id: message.id.to_s
    )

    get "/api/v1/reviewer/companies/#{company.id}/reports/#{report.id}/workspace",
        headers: auth_headers_for(reviewer)

    discussions = JSON.parse(response.body)["discussions"]
    expect(discussions.length).to eq(1)
    expect(discussions.first["body"]).to be_present
  end
end
