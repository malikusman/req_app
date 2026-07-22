# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Billing mock checkout (BLK-5)", type: :request do
  let(:company) { create(:company) }
  let(:subscription) { company.subscription }
  let(:token) { "mock-token-blk5" }

  before do
    allow(Rails.cache).to receive(:read).with("mock_checkout:#{token}").and_return(
      { "company_id" => company.id, "plan" => "starter" }
    )
    allow(Rails.cache).to receive(:delete).with("mock_checkout:#{token}")
  end

  after { Rails.cache.clear }

  it "returns 404 when mocks are disallowed" do
    allow(MocksAllowed).to receive(:allowed?).and_return(false)

    get "/api/v1/billing/mock_checkout", params: { token: token }

    expect(response).to have_http_status(:not_found)
    expect(subscription.reload.status).to eq("trial")
  end

  it "activates the plan when mocks are allowed" do
    allow(MocksAllowed).to receive(:allowed?).and_return(true)

    get "/api/v1/billing/mock_checkout", params: { token: token }

    expect(response).to have_http_status(:redirect)
    expect(subscription.reload.status).to eq("active")
    expect(subscription.plan).to eq("starter")
  end
end
