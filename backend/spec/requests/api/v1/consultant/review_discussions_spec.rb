# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant report discussions", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:consultant) { create(:consultant_user) }
  let(:co_consultant) { create(:consultant_user, name: "Co Consultant") }
  let!(:report) { create(:report, :ready, company: company) }
  let!(:review) { create(:report_review, report: report, consultant_user: consultant, company: company) }
  let!(:co_review) { create(:report_review, report: report, consultant_user: co_consultant, company: company) }
  let(:employee) { create(:employee, company: company) }
  let!(:conversation) { create(:conversation, employee: employee, company: company) }
  let!(:message) { create(:message, conversation: conversation, direction: "inbound", body: "We use Slack") }

  before do
    create(:consultant_assignment, company: company, consultant_user: consultant)
    create(:consultant_assignment, company: company, consultant_user: co_consultant)
  end

  it "creates a co-consultant discussion on a message anchor" do
    expect do
      post "/api/v1/consultant/companies/#{company.id}/reports/#{report.id}/discussions",
           params: {
             target_type: "consultant",
             target_consultant_user_id: co_consultant.id,
             anchor_type: "message",
             anchor_id: message.id,
             body: "Does this match your read?"
           },
           headers: auth_headers_for(consultant)
    end.to change(ReviewDiscussion, :count).by(1)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["discussion"]["anchor_type"]).to eq("message")
    expect(body["discussion"]["target_type"]).to eq("consultant")
  end

  it "includes discussions in workspace payload" do
    create(
      :review_discussion,
      report: report,
      company: company,
      author_consultant_user: consultant,
      target_consultant_user: co_consultant,
      anchor_type: "message",
      anchor_id: message.id.to_s
    )

    get "/api/v1/consultant/companies/#{company.id}/reports/#{report.id}/workspace",
        headers: auth_headers_for(consultant)

    discussions = JSON.parse(response.body)["discussions"]
    expect(discussions.length).to eq(1)
    expect(discussions.first["body"]).to be_present
  end
end
