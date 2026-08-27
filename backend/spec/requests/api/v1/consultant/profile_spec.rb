# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Consultant::Profile", type: :request do
  before do
    ConsultantExperience.delete_all
    ConsultantUser.delete_all
  end

  let!(:consultant) { create(:consultant_user) }
  let(:headers) { auth_headers_for(consultant) }

  describe "GET /api/v1/consultant/profile" do
    it "returns profile payload" do
      get "/api/v1/consultant/profile", headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["profile"]["profile_status"]).to eq("draft")
      expect(body["profile"]["completeness"]).to include("percent")
    end
  end

  describe "PATCH /api/v1/consultant/profile" do
    it "updates profile fields and experiences" do
      patch "/api/v1/consultant/profile",
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
      consultant.reload
      expect(consultant.headline).to eq("Supply chain lead")
      expect(consultant.consultant_experiences.count).to eq(1)
      expect(consultant.profile_completed_at).to be_present
    end

    it "publishes when complete" do
      patch "/api/v1/consultant/profile",
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
      expect(consultant.reload.profile_status).to eq("published")
    end

    it "publishes even when incomplete" do
      patch "/api/v1/consultant/profile", params: { publish: true }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(consultant.reload.profile_status).to eq("published")
    end
  end
end
