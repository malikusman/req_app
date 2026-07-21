# frozen_string_literal: true

module Billing
  class CheckoutService
    PLANS = {
      "starter" => { amount_cents: 49900, conversations: 100 },
      "growth" => { amount_cents: 149900, conversations: 500 }
    }.freeze

    def self.create_session(company:, plan:)
      new(company: company, plan: plan).create_session
    end

    def initialize(company:, plan:)
      @company = company
      @plan = plan
    end

    def create_session
      unless PLANS.key?(@plan)
        raise ArgumentError, "Invalid plan: #{@plan}"
      end

      if stripe_configured?
        stripe_checkout_url
      else
        MocksAllowed.require!("Stripe")
        mock_checkout_url
      end
    end

    private

    def stripe_configured?
      ENV["STRIPE_SECRET_KEY"].present?
    end

    def stripe_checkout_url
      require "stripe"
      Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

      customer_id = ensure_stripe_customer
      session = Stripe::Checkout::Session.create(
        customer: customer_id,
        mode: "subscription",
        line_items: [{ price: stripe_price_id, quantity: 1 }],
        success_url: "#{app_host}/company/billing?success=1",
        cancel_url: "#{app_host}/company/billing?canceled=1",
        metadata: { company_id: @company.id, plan: @plan }
      )
      { checkout_url: session.url, mock: false }
    end

    def ensure_stripe_customer
      sub = @company.subscription
      return sub.stripe_customer_id if sub.stripe_customer_id.present?

      customer = Stripe::Customer.create(
        email: @company.company_users.find_by(role: "company_admin")&.email,
        metadata: { company_id: @company.id }
      )
      sub.update!(stripe_customer_id: customer.id)
      customer.id
    end

    def stripe_price_id
      ENV.fetch("STRIPE_PRICE_#{@plan.upcase}", "price_mock_#{@plan}")
    end

    def mock_checkout_url
      token = SecureRandom.hex(16)
      Rails.cache.write(
        "mock_checkout:#{token}",
        { company_id: @company.id, plan: @plan },
        expires_in: 1.hour
      )
      api_host = ENV.fetch("API_PUBLIC_HOST", "http://localhost:3000")
      {
        checkout_url: "#{api_host}/api/v1/billing/mock_checkout?token=#{token}",
        mock: true
      }
    end

    def app_host
      ENV.fetch("APP_HOST", "http://localhost:5173")
    end
  end
end
