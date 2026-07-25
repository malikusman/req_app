# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform registrations", type: :request do
  let(:platform_user) { create(:platform_user) }
  let(:headers) { auth_headers_for(platform_user) }

  def create_pending_registration
    Registrations::CreateCompanyRegistration.call(
      company_name: "Pending Co",
      admin_name: "Pat Pending",
      admin_email: "pat@pending.test",
      admin_phone: "+971500000001"
    )
  end

  it "lists pending company registrations and reviewer applications" do
    create_pending_registration
    create(:reviewer_user, status: "pending", email: "rev@pending.test", password: "password123")

    get "/api/v1/platform/registrations", headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["company_registrations"].size).to be >= 1
    expect(body["reviewer_applications"].size).to be >= 1
  end

  it "approves a company registration, starts a trial, and emails set-password" do
    registration = create_pending_registration

    expect {
      post "/api/v1/platform/registrations/companies/#{registration.id}/approve", headers: headers
    }.to have_enqueued_mail(SignupMailer, :company_registration_approved)

    expect(response).to have_http_status(:ok)
    registration.reload
    expect(registration.status).to eq("approved")
    expect(registration.company.approval_status).to eq("approved")
    expect(registration.company.subscription).to be_present
    expect(registration.company_user.status).to eq("pending")
  end

  it "rejects a company registration" do
    registration = create_pending_registration

    expect {
      post "/api/v1/platform/registrations/companies/#{registration.id}/reject",
           headers: headers,
           params: { review_note: "Not a fit" }
    }.to have_enqueued_mail(SignupMailer, :company_registration_rejected)

    expect(response).to have_http_status(:ok)
    expect(registration.reload.status).to eq("rejected")
    expect(registration.company.approval_status).to eq("rejected")
    expect(registration.company_user.status).to eq("deactivated")
  end

  it "approves a reviewer application" do
    reviewer = create(:reviewer_user, status: "pending", email: "newrev@test.com", password: "password123")

    expect {
      post "/api/v1/platform/registrations/reviewers/#{reviewer.id}/approve", headers: headers
    }.to have_enqueued_mail(SignupMailer, :reviewer_application_approved)

    expect(response).to have_http_status(:ok)
    expect(reviewer.reload.status).to eq("active")
    expect(reviewer.approved_at).to be_present
  end
end
