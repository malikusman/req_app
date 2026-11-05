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

  it "starts reading the website straight away, so proposals are ready at first sign-in" do
    expect {
      post "/api/v1/platform/engagements", params: params, headers: headers, as: :json
    }.to have_enqueued_job(WebsitePrefillJob)
    expect(Engagement.last.prefill_status).to eq("pending")
  end

  it "can read the website again on request" do
    engagement = create(:engagement, company: create(:company, website_url: "https://alnoor.example"))
    expect {
      post "/api/v1/platform/engagements/#{engagement.id}/reread_website", headers: headers
    }.to have_enqueued_job(WebsitePrefillJob).with(engagement.id)
    expect(response).to have_http_status(:ok)
  end

  it "doesn't start a second read while one is under way, but restarts one that is stuck" do
    engagement = create(:engagement, company: create(:company, website_url: "https://alnoor.example"),
                                     prefill_status: "running")
    post "/api/v1/platform/engagements/#{engagement.id}/reread_website", headers: headers
    expect(response).to have_http_status(:conflict)

    travel 16.minutes do
      expect {
        post "/api/v1/platform/engagements/#{engagement.id}/reread_website", headers: headers
      }.to have_enqueued_job(WebsitePrefillJob).with(engagement.id)
      expect(response).to have_http_status(:ok)
    end
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

  describe "settling planned counts before pricing (Doc 07 §10)" do
    let(:key_user) { create(:company_user) }
    let(:engagement) do
      create(:engagement, status: "KEY_PERSON_DISCOVERY", key_user: key_user,
                          planned_departments: [{ "name" => "Sales", "count" => "UNKNOWN" }])
    end

    def settle(rows)
      patch "/api/v1/platform/engagements/#{engagement.id}", params: { engagement: { planned_departments: rows } },
                                                             headers: headers, as: :json
    end

    it "sets the counts and moves on to pricing once the key user's conversation is done" do
      own = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", source: "KEY_USER",
                                            company_user: key_user, name: key_user.name)
      create(:conversation_session, participant: own, state: "COMPLETE")

      settle([{ name: "Sales", count: "3" }, { name: "sales", count: "9" }])

      expect(engagement.reload.planned_departments).to eq([{ "name" => "Sales", "count" => 3 }])
      expect(engagement.status).to eq("STAGE_1_PRICING")
      expect(engagement.status_history.last).to include("by_type" => "PlatformUser")
    end

    it "only sets them while the leadership conversations are on" do
      engagement.update!(status: "STAGE_1_PRICING")
      settle([{ name: "Sales", count: "3" }])
      expect(engagement.reload.planned_departments).to eq([{ "name" => "Sales", "count" => "UNKNOWN" }])
    end
  end
end
