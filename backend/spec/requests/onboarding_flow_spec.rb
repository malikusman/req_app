# frozen_string_literal: true

require "rails_helper"
require "resolv"

# Company onboarding end to end through the API (Doc 07): Mjadi sets up the
# engagement → the website is read → the key user accepts the invitation,
# confirms a proposal, answers the facts, plans who takes part, acknowledges and
# submits → the engagement moves on to the conversation with leadership.
RSpec.describe "Company onboarding, end to end", type: :request do
  include ActiveJob::TestHelper

  let(:platform_user) { create(:platform_user) }
  let(:consultant) { create(:consultant_user) }
  let(:client) { instance_double(Openai::Client, configured?: true) }
  let(:home) { "https://example-trading.ae/" }

  before do
    ENV["AI_PREFILL"] = "true"
    allow(Resolv).to receive(:getaddresses).and_return(["93.184.216.34"])
    stub_request(:get, home).to_return(body: Rails.root.join("spec/fixtures/websites/trading_home.html").read)
    stub_request(:get, %r{example-trading\.ae/.+}).to_return(status: 404)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    allow(Openai::Client).to receive(:new).and_return(client)
    allow(client).to receive(:website_prefill).and_return(
      "entity_check" => { "website_describes" => "SINGLE_COMPANY" },
      "candidates" => [{ "field" => "industry", "value" => "Wholesale distribution — tailoring materials",
                         "display_text" => "Wholesaler of tailoring materials", "confidence" => "HIGH",
                         "source_url" => home, "evidence_excerpt" => "leading wholesalers of tailoring materials" }]
    )
  end

  it "takes a new client from engagement set-up to the leadership conversation" do
    # 1. Mjadi sets up the engagement; the website is read in the background.
    perform_enqueued_jobs(only: WebsitePrefillJob) do
      post "/api/v1/platform/engagements", headers: auth_headers_for(platform_user), as: :json, params: {
        engagement: { company_name: "Example Trading LLC", website_url: "example-trading.ae", scope_type: "COMPANY",
                      lead_consultant_id: consultant.id, languages: %w[en],
                      key_user: { name: "Huda Saleh", email: "huda@example-trading.ae", role_title: "GM" } }
      }
    end
    expect(response).to have_http_status(:created)
    engagement = Engagement.last
    expect(engagement.reload.prefill_status).to eq("done")
    key_user = engagement.key_user

    # 2. The key user sets a password from the invitation and signs in.
    token = Auth::PasswordResetToken.generate(key_user, ttl: Auth::PasswordResetToken::INVITATION_TTL)
    Auth::SetPassword.call(token: token, password: "onboarding-1", password_confirmation: "onboarding-1")
    post "/api/v1/auth/company/login", params: { email: "huda@example-trading.ae", password: "onboarding-1" }
    expect(response).to have_http_status(:ok)
    headers = auth_headers_for(key_user.reload)
    expect(engagement.reload.status).to eq("ONBOARDING")

    # 3. They confirm what the website said, and answer the rest.
    get "/api/v1/company/onboarding", headers: headers
    proposal = JSON.parse(response.body).dig("prefill", "candidates", 0)
    post "/api/v1/company/onboarding/prefill_candidates/#{proposal['id']}/confirm", headers: headers
    patch "/api/v1/company/onboarding/questionnaire/answers", headers: headers, as: :json, params: { answers: {
      o02_headcount: "11–50", o07_channels: %w[WhatsApp], o11_constraints: "Not sure",
      p1_departments: %w[Procurement Sales], p2_department_counts: { "Procurement" => "2", "Sales" => "Not sure" }
    } }
    post "/api/v1/company/onboarding/participants", headers: headers, as: :json,
                                                    params: { participant: { participant_type: "KEY_PERSON",
                                                                             name: "Rania Haddad" } }

    # 4. They acknowledge and submit.
    post "/api/v1/company/onboarding/submit", headers: headers, as: :json,
                                              params: { answers: {}, confidentiality_acknowledged: true }
    expect(response).to have_http_status(:ok)

    company = engagement.company.reload
    expect(engagement.reload.status).to eq("KEY_PERSON_DISCOVERY")
    expect(company.profile_provenance.dig("industry", "source")).to eq("PREFILL_CONFIRMED")
    expect(company.profile_provenance.dig("size_band", "source")).to eq("USER_ENTERED")
    expect(company.profile_provenance["security_constraints"]).to include("unknown" => true)
    expect(engagement.planned_participant_count).to be_nil # Sales still "Not sure": settled before pricing
    expect(engagement.participants.key_persons.pluck(:name)).to eq(["Rania Haddad"])
    expect(company.subscription).to be_nil
  end
end
