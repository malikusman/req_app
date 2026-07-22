# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public password resets", type: :request do
  let(:company) { create(:company, approval_status: "approved", approved_at: 1.day.ago) }
  let(:user) { create(:company_user, company: company, status: "active", email: "reset@example.com") }

  it "enqueues a reset email for a known company user" do
    user
    expect {
      post "/api/v1/public/password_resets", params: { portal: "company", email: user.email }
    }.to have_enqueued_mail(SignupMailer, :password_reset)
    expect(response).to have_http_status(:ok)
  end

  it "still returns ok for unknown emails" do
    post "/api/v1/public/password_resets", params: { portal: "company", email: "nobody@example.com" }
    expect(response).to have_http_status(:ok)
  end

  it "sets a password from a valid token and activates a pending company user" do
    pending_user = create(:company_user, company: company, status: "pending", email: "pending@example.com")
    token = Auth::PasswordResetToken.generate(pending_user)

    put "/api/v1/public/password_resets/confirm", params: {
      token: token,
      password: "newpassword1",
      password_confirmation: "newpassword1"
    }

    expect(response).to have_http_status(:ok)
    expect(pending_user.reload.status).to eq("active")
    expect(pending_user.authenticate("newpassword1")).to be_truthy
  end
end
