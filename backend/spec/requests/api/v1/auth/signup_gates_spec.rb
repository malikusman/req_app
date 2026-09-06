# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth gates for pending signup", type: :request do
  it "blocks pending company users from logging in" do
    company = create(:company, approval_status: "pending_approval")
    create(:company_user, company: company, status: "pending", email: "pending@co.test", password: "password123")

    post "/api/v1/auth/company/login", params: { email: "pending@co.test", password: "password123" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "blocks active users of unapproved companies" do
    company = create(:company, approval_status: "pending_approval")
    # Edge case: status active but company not approved
    create(:company_user, company: company, status: "active", email: "active@co.test", password: "password123")

    post "/api/v1/auth/company/login", params: { email: "active@co.test", password: "password123" }
    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)["error"]).to match(/pending approval/i)
  end

  it "blocks pending consultants from logging in" do
    create(:consultant_user, status: "pending", email: "pending@rev.test", password: "password123")

    post "/api/v1/auth/consultant/login", params: { email: "pending@rev.test", password: "password123" }
    expect(response).to have_http_status(:unauthorized)
  end
end
