# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Stripe webhooks (BLK-5)", type: :request do
  let(:company) { create(:company) }
  let(:subscription) { company.subscription }

  def post_stripe_webhook(body, headers: {})
    post "/api/v1/webhooks/stripe",
         params: body,
         headers: { "CONTENT_TYPE" => "application/json" }.merge(headers)
  end

  def forged_checkout_payload(company_id:, plan: "starter")
    {
      "type" => "checkout.session.completed",
      "data" => {
        "object" => {
          "customer" => "cus_forged",
          "subscription" => "sub_forged",
          "metadata" => { "company_id" => company_id.to_s, "plan" => plan }
        }
      }
    }.to_json
  end

  context "when STRIPE_WEBHOOK_SECRET is blank" do
    around do |example|
      previous = ENV["STRIPE_WEBHOOK_SECRET"]
      ENV.delete("STRIPE_WEBHOOK_SECRET")
      example.run
    ensure
      if previous
        ENV["STRIPE_WEBHOOK_SECRET"] = previous
      else
        ENV.delete("STRIPE_WEBHOOK_SECRET")
      end
    end

    it "rejects unsigned payloads when mocks are disallowed" do
      allow(MocksAllowed).to receive(:allowed?).and_return(false)

      expect {
        post_stripe_webhook(forged_checkout_payload(company_id: company.id))
      }.not_to(change { subscription.reload.status })

      expect(response).to have_http_status(:bad_request)
    end

    it "accepts JSON payloads when mocks are allowed (dev ergonomics)" do
      allow(MocksAllowed).to receive(:allowed?).and_return(true)

      post_stripe_webhook(forged_checkout_payload(company_id: company.id))

      expect(response).to have_http_status(:ok)
      expect(subscription.reload.status).to eq("active")
      expect(subscription.plan).to eq("starter")
    end
  end

  context "when STRIPE_WEBHOOK_SECRET is set" do
    around do |example|
      previous = ENV["STRIPE_WEBHOOK_SECRET"]
      ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test_secret"
      example.run
    ensure
      if previous
        ENV["STRIPE_WEBHOOK_SECRET"] = previous
      else
        ENV.delete("STRIPE_WEBHOOK_SECRET")
      end
    end

    it "rejects payloads without a valid Stripe signature" do
      expect {
        post_stripe_webhook(
          forged_checkout_payload(company_id: company.id),
          headers: { "HTTP_STRIPE_SIGNATURE" => "t=1,v1=deadbeef" }
        )
      }.not_to(change { subscription.reload.status })

      expect(response).to have_http_status(:bad_request)
    end
  end
end
