# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::StripeWebhookHandler do
  let(:company) { create(:company) }
  let(:subscription) { company.subscription }

  it "activates the company subscription on checkout.session.completed" do
    event = {
      "type" => "checkout.session.completed",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "subscription" => "sub_123",
          "metadata" => { "company_id" => company.id.to_s, "plan" => "growth" }
        }
      }
    }

    described_class.call(event: event)

    subscription.reload
    expect(subscription.status).to eq("active")
    expect(subscription.plan).to eq("growth")
    expect(subscription.stripe_customer_id).to eq("cus_123")
    expect(subscription.stripe_subscription_id).to eq("sub_123")
  end

  it "ignores events without a company_id" do
    event = {
      "type" => "checkout.session.completed",
      "data" => { "object" => { "metadata" => {} } }
    }

    expect {
      described_class.call(event: event)
    }.not_to(change { subscription.reload.status })
  end
end
