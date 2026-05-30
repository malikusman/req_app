# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Reviewer::Profile", type: :request do
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

  let!(:reviewer) { create(:reviewer_user) }
  let(:headers) { auth_headers_for(reviewer) }

  describe "GET /api/v1/reviewer/profile" do
    it "returns profile payload" do
      get "/api/v1/reviewer/profile", headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["profile"]["profile_status"]).to eq("draft")
      expect(body["profile"]["completeness"]).to include("percent")
    end
  end

  describe "PATCH /api/v1/reviewer/profile" do
    it "updates profile fields and experiences" do
      patch "/api/v1/reviewer/profile",
            params: {
              headline: "Supply chain lead",
              bio: "x" * 80,
              linkedin_url: "https://linkedin.com/in/expert",
              expertise_tags: %w[Finance Controls ERP],
              experiences: [
                { organization: "BigCo", title: "VP Ops", start_year: 2010, end_year: 2020 }
              ]
            },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      reviewer.reload
      expect(reviewer.headline).to eq("Supply chain lead")
      expect(reviewer.reviewer_experiences.count).to eq(1)
      expect(reviewer.profile_completed_at).to be_present
    end

    it "publishes when complete" do
      patch "/api/v1/reviewer/profile",
            params: {
              headline: "Finance leader",
              bio: "y" * 80,
              linkedin_url: "https://linkedin.com/in/finance",
              expertise_tags: %w[Finance Controls Risk],
              experiences: [{ organization: "Bank", title: "CFO", start_year: 2005 }],
              publish: true
            },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(reviewer.reload.profile_status).to eq("pending_review")
    end

    it "rejects publish when incomplete" do
      patch "/api/v1/reviewer/profile", params: { publish: true }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not allow changing email from profile update" do
      original_email = reviewer.email

      patch "/api/v1/reviewer/profile",
            params: { email: "changed-#{SecureRandom.hex(2)}@example.com", name: "Updated Name" },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      reviewer.reload
      expect(reviewer.email).to eq(original_email)
      expect(reviewer.name).to eq("Updated Name")
    end
  end
end
