# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Platform::Reviewers", type: :request do
  let(:platform_user) { create(:platform_user) }
  let(:headers) { auth_headers_for(platform_user) }

  before { create_list(:reviewer_user, 2) }

  describe "GET /api/v1/platform/reviewers" do
    it "lists reviewers for platform user" do
      get "/api/v1/platform/reviewers", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["reviewers"].length).to eq(2)
    end
  end
end
