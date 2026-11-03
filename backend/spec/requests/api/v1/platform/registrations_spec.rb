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

  it "lists pending company registrations and consultant applications" do
    create_pending_registration
    create(:consultant_user, status: "pending", email: "rev@pending.test", password: "password123")

    get "/api/v1/platform/registrations", headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["company_registrations"].size).to be >= 1
    expect(body["consultant_applications"].size).to be >= 1
  end

  it "approves a company registration through engagement set-up and invites the requester" do
    registration = create_pending_registration
    consultant = create(:consultant_user)

    expect {
      post "/api/v1/platform/registrations/companies/#{registration.id}/approve",
           headers: headers,
           params: { engagement: { scope_type: "COMPANY", lead_consultant_id: consultant.id, languages: %w[en ar],
                                   proposal_reference: "P-2026-014" } },
           as: :json
    }.to have_enqueued_mail(SignupMailer, :engagement_invitation)

    expect(response).to have_http_status(:ok)
    registration.reload
    expect(registration.status).to eq("approved")
    expect(registration.company.approval_status).to eq("approved")
    engagement = registration.company.current_engagement
    expect(engagement.status).to eq("SET_UP")
    expect(engagement.key_user).to eq(registration.company_user)
    expect(engagement.lead_consultant).to eq(consultant)
    expect(engagement.languages).to eq(%w[en ar])
    expect(registration.company.subscription).to be_nil
    expect(registration.company_user.status).to eq("pending")
  end

  it "leaves the request pending when the engagement details are incomplete" do
    registration = create_pending_registration

    post "/api/v1/platform/registrations/companies/#{registration.id}/approve",
         headers: headers, params: { engagement: { languages: ["en"] } }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to match(/lead consultant/)
    expect(registration.reload.status).to eq("pending")
    expect(registration.company.reload.approval_status).to eq("pending_approval")
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

  it "approves a consultant application" do
    consultant = create(:consultant_user, status: "pending", email: "newrev@test.com", password: "password123")

    expect {
      post "/api/v1/platform/registrations/consultants/#{consultant.id}/approve", headers: headers
    }.to have_enqueued_mail(SignupMailer, :consultant_application_approved)

    expect(response).to have_http_status(:ok)
    expect(consultant.reload.status).to eq("active")
    expect(consultant.approved_at).to be_present
  end
end
