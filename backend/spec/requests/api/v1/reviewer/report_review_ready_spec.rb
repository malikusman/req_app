# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reviewer report ready and platform release", type: :request do
  let!(:platform_user) { create(:platform_user) }
  let!(:company) { create(:company, :onboarded) }
  let!(:reviewer) { create(:reviewer_user, email: "ready-#{SecureRandom.hex(4)}@example.com") }
  let!(:assignment) { create(:reviewer_assignment, company: company, reviewer_user: reviewer) }
  let!(:report) do
    create(:report,
           company: company,
           status: "ready",
           visibility: "internal_only",
           review_workflow_status: "awaiting_reviewers",
           version: 1)
  end
  let!(:report_review) do
    create(:report_review, report: report, reviewer_user: reviewer, company: company, status: "pending")
  end

  describe "POST mark_ready" do
    it "marks reviewer satisfied and visible in sign_off_status" do
      post "/api/v1/reviewer/companies/#{company.id}/reports/#{report.id}/review/mark_ready",
           params: { ready_note: "All sections look good" },
           headers: auth_headers_for(reviewer),
           as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["review"]["sign_off_status"]).to eq("ready")
      expect(body["review"]["ready_at"]).to be_present
    end
  end

  describe "POST platform approve (release)" do
    before do
      report_review.mark_ready!
      report_review.submit!
      report.update!(review_workflow_status: "reviews_complete")
    end

    it "releases report to company" do
      post "/api/v1/platform/companies/#{company.id}/reports/#{report.id}/approve",
           headers: auth_headers_for(platform_user)

      expect(response).to have_http_status(:ok)
      report.reload
      expect(report.visibility).to eq("shared_with_company")
      expect(report.review_workflow_status).to eq("platform_approved")
    end
  end
end
