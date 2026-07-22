# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CheckoutService do
  let(:company) { create(:company) }

  it "raises when Stripe is not configured and mocks are disallowed" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("STRIPE_SECRET_KEY").and_return(nil)
    allow(MocksAllowed).to receive(:allowed?).and_return(false)

    expect {
      described_class.create_session(company: company, plan: "starter")
    }.to raise_error(/Stripe is not configured/)
  end

  it "returns a mock checkout URL when mocks are allowed and Stripe is unset" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("STRIPE_SECRET_KEY").and_return(nil)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("API_PUBLIC_HOST", anything).and_return("http://localhost:3000")
    allow(MocksAllowed).to receive(:allowed?).and_return(true)
    allow(MocksAllowed).to receive(:require!).with("Stripe").and_return(nil)

    result = described_class.create_session(company: company, plan: "starter")

    expect(result[:mock]).to eq(true)
    expect(result[:checkout_url]).to include("/api/v1/billing/mock_checkout")
  end

  it "rejects unknown plans" do
    expect {
      described_class.create_session(company: company, plan: "enterprise")
    }.to raise_error(ArgumentError, /Invalid plan/)
  end
end
