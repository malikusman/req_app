# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::Billing", type: :request do
  let!(:company) { create(:company, :onboarded) }
  let!(:company_user) { create(:company_user, company: company, role: "company_admin") }

  describe "GET /api/v1/company/billing" do
    it "returns billing events when available" do
      company.billing_events.create!(
        event_type: "checkout_started",
        status: "pending",
        amount_cents: 49_900,
        occurred_at: Time.current
      )

      get "/api/v1/company/billing", headers: auth_headers_for(company_user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["events"]).to be_present
      expect(response.parsed_body["events"].first["event_type"]).to eq("checkout_started")
    end
  end
end
