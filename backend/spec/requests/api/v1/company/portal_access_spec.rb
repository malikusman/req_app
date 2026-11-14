# frozen_string_literal: true

require "rails_helper"

# A client mid-engagement must never be locked out by a lapsed trial: access
# follows the engagement (Doc 17 §2 — a fixed-fee engagement, not a subscription).
RSpec.describe "Company portal access", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:company_user, company: company) }

  before { company.subscription.update!(status: "trial", trial_ends_at: 1.day.ago) }

  it "stays open while an engagement is in progress" do
    create(:engagement, company: company, status: "ONBOARDING")

    get "/api/v1/company/onboarding", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
  end

  it "closes once the engagement is closed" do
    create(:engagement, company: company, status: "CLOSED")

    get "/api/v1/company/onboarding", headers: auth_headers_for(user)

    expect(response).to have_http_status(:forbidden)
  end

  it "falls back to the subscription for a company without an engagement" do
    get "/api/v1/company/onboarding", headers: auth_headers_for(user)

    expect(response).to have_http_status(:forbidden)
  end
end
