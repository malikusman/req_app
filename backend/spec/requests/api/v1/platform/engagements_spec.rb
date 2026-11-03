# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform engagement set-up", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:platform_user) { create(:platform_user) }
  let(:headers) { auth_headers_for(platform_user) }
  let(:consultant) { create(:consultant_user) }
  let(:params) do
    {
      engagement: {
        company_name: "Al Noor Trading",
        website_url: "alnoor.example",
        scope_type: "DEPARTMENT",
        departments_in_scope: %w[Procurement Finance],
        lead_consultant_id: consultant.id,
        languages: %w[ar en],
        proposal_reference: "P-2026-021",
        key_user: { name: "Huda Saleh", role_title: "Operations Manager", email: "Huda@AlNoor.example",
                    phone: "+971500000123" }
      }
    }
  end

  it "creates the company, engagement and key user, assigns the lead, and invites — with no trial" do
    expect {
      post "/api/v1/platform/engagements", params: params, headers: headers, as: :json
    }.to change(Engagement, :count).by(1)
      .and have_enqueued_mail(SignupMailer, :engagement_invitation)

    expect(response).to have_http_status(:created)
    engagement = Engagement.last
    company = engagement.company
    expect(engagement).to have_attributes(status: "SET_UP", scope_type: "DEPARTMENT",
                                          departments_in_scope: %w[Procurement Finance],
                                          languages: %w[ar en], proposal_reference: "P-2026-021",
                                          lead_consultant: consultant)
    expect(company).to have_attributes(name: "Al Noor Trading", approval_status: "approved",
                                       website_url: "https://alnoor.example", locale: "ar")
    expect(company.subscription).to be_nil
    expect(company.consultant_assignments.active.pluck(:consultant_user_id)).to eq([consultant.id])
    expect(engagement.key_user).to have_attributes(email: "huda@alnoor.example", status: "pending",
                                                   role: "company_admin", job_title: "Operations Manager")
    expect(PlatformAuditLog.where(action: "engagement_created")).to exist
  end

  it "needs departments when the scope is departments" do
    params[:engagement][:departments_in_scope] = []
    post "/api/v1/platform/engagements", params: params, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Company.where(name: "Al Noor Trading")).not_to exist
  end

  it "refuses a key user email that already has an account" do
    create(:company_user, email: "huda@alnoor.example")
    post "/api/v1/platform/engagements", params: params, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to match(/already exists/)
  end

  it "is for Mjadi only" do
    post "/api/v1/platform/engagements", params: params, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  describe "the key user's invitation" do
    before { post "/api/v1/platform/engagements", params: params, headers: headers, as: :json }

    let(:engagement) { Engagement.last }

    it "can be sent again while the key user hasn't set a password" do
      expect {
        post "/api/v1/platform/engagements/#{engagement.id}/resend_invitation", headers: headers
      }.to have_enqueued_mail(SignupMailer, :engagement_invitation)
      expect(response).to have_http_status(:ok)
    end

    it "opens onboarding when the key user sets their password from it, days later" do
      token = Auth::PasswordResetToken.generate(engagement.key_user, ttl: Auth::PasswordResetToken::INVITATION_TTL)
      travel 6.days do
        Auth::SetPassword.call(token: token, password: "a-strong-pass", password_confirmation: "a-strong-pass")
      end

      expect(engagement.reload.status).to eq("ONBOARDING")
      expect(engagement.key_user.status).to eq("active")
      expect(engagement.status_history.last).to include("from" => "SET_UP", "to" => "ONBOARDING")
    end

    it "is not resent once the key user is active" do
      engagement.key_user.update!(status: "active")
      post "/api/v1/platform/engagements/#{engagement.id}/resend_invitation", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "lets the scope be corrected only before onboarding is handed over" do
    engagement = create(:engagement, status: "KEY_PERSON_DISCOVERY", scope_type: "COMPANY")
    patch "/api/v1/platform/engagements/#{engagement.id}",
          params: { engagement: { scope_type: "DEPARTMENT", departments_in_scope: ["Sales"],
                                  proposal_reference: "P-9" } },
          headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(engagement.reload).to have_attributes(scope_type: "COMPANY", proposal_reference: "P-9")
  end
end
