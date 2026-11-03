# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Platform::Companies", type: :request do
  describe "GET /api/v1/platform/companies" do
    let(:platform_user) { create(:platform_user) }

    before { create_list(:company, 2) }

    it "lists companies for authenticated platform user" do
      get "/api/v1/platform/companies", headers: auth_headers_for(platform_user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["companies"].length).to be >= 2
    end

    it "returns unauthorized without token" do
      get "/api/v1/platform/companies"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  it "no longer creates companies directly, so no password is ever chosen or emailed for a client" do
    post "/api/v1/platform/companies", headers: auth_headers_for(create(:platform_user)),
                                       params: { company: { name: "Acme Co" } }

    expect(response).to have_http_status(:not_found)
  end
end
