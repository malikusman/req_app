# frozen_string_literal: true

require "rails_helper"

# Transition cover for the Reviewer -> Consultant rename.
#
# These paths exist only so things already in the wild keep working: tokens issued
# before the rename (24h TTL), links in sent emails, and cached frontend bundles.
# When they are removed, these specs should be removed with them — that is the
# signal that the compatibility window is closed on purpose rather than by
# accident.
RSpec.describe "Reviewer -> Consultant rename compatibility", type: :request do
  let!(:consultant) { create(:consultant_user, email: "c@test.com", password: "password123") }

  def token_with(aud:, sub_prefix:)
    JsonWebToken.encode(
      { sub: "#{sub_prefix}:#{consultant.id}", aud: aud, role: aud, jti: consultant.jti }
    )
  end

  describe "JWT audience" do
    it "accepts a token issued after the rename" do
      get "/api/v1/consultant/me",
          headers: { "Authorization" => "Bearer #{token_with(aud: 'consultant', sub_prefix: 'consultant_user')}" }

      expect(response).to have_http_status(:ok)
    end

    it "accepts a token issued before the rename" do
      get "/api/v1/consultant/me",
          headers: { "Authorization" => "Bearer #{token_with(aud: 'reviewer', sub_prefix: 'reviewer_user')}" }

      expect(response).to have_http_status(:ok)
    end

    it "still rejects an unrelated audience" do
      get "/api/v1/consultant/me",
          headers: { "Authorization" => "Bearer #{token_with(aud: 'company', sub_prefix: 'company_user')}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "pre-rename routes" do
    it "serves the old login path" do
      post "/api/v1/auth/reviewer/login", params: { email: "c@test.com", password: "password123" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["token"]).to be_present
    end

    it "serves the old application path" do
      post "/api/v1/public/reviewer_applications",
           params: { consultant: { name: "A Consultant", email: "apply@test.com" } }

      # Whatever the controller decides about the payload, the route must resolve —
      # a 404 here means an in-the-wild link broke.
      expect(response).not_to have_http_status(:not_found)
    end
  end

  describe "password reset links sent before the rename" do
    it "still resolves portal=reviewer to a consultant" do
      expect(Auth::RequestPasswordReset.call(portal: "reviewer", email: "c@test.com")).to be(true)
    end
  end
end
