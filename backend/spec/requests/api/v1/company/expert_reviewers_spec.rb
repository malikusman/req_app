# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::ExpertReviewers", type: :request do
  before do
    ReportReviewComment.delete_all
    ReportReviewSectionState.delete_all
    ReportReview.delete_all
    ReviewerInfoReply.delete_all
    ReviewerInfoRequest.delete_all
    ReviewerChatMessage.delete_all
    ReviewerAssignment.delete_all
    ReviewerExperience.delete_all
    ReviewerUser.delete_all
  end

  let!(:company) { create(:company, :onboarded) }
  let!(:company_user) { create(:company_user, company: company) }
  let!(:reviewer) { create(:reviewer_user, :published_profile) }
  let!(:assignment) { create(:reviewer_assignment, company: company, reviewer_user: reviewer) }

  describe "GET /api/v1/company/expert_reviewers" do
    it "returns published assigned reviewers only" do
      draft = create(:reviewer_user, headline: "Draft only")
      create(:reviewer_assignment, company: company, reviewer_user: draft)

      get "/api/v1/company/expert_reviewers", headers: auth_headers_for(company_user)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["expert_reviewers"].map { |r| r["id"] }
      expect(ids).to eq([reviewer.id])
      expect(response.parsed_body["pending_review_count"]).to eq(0)
    end

    it "reports pending reviewer approvals for company visibility" do
      pending = create(:reviewer_user, profile_status: "pending_review", platform_verified_at: nil)
      create(:reviewer_assignment, company: company, reviewer_user: pending)

      get "/api/v1/company/expert_reviewers", headers: auth_headers_for(company_user)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["expert_reviewers"].map { |r| r["id"] }
      expect(ids).to eq([reviewer.id])
      expect(response.parsed_body["pending_review_count"]).to eq(1)
    end
  end
end
