# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::ExpertReviewers", type: :request do
  before do
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
    end
  end
end
