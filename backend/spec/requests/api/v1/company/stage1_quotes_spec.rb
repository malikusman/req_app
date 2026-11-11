# frozen_string_literal: true

require "rails_helper"

# The client's Stage 1 proposal (Doc 17 §10, Doc 21 §10, §44): nothing reaches
# them before an administrator approves it; nothing internal ever does; only
# the key user accepts, and acceptance starts Stage 1.
RSpec.describe "Company: the Stage 1 proposal", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  # Words that would mean internal pricing data reached a client (Doc 05 §18).
  INTERNAL = /margin|internal|cost|hours|rate_card|override|floor|estimate|admin_explanation|risk_signals/i

  let(:company) { create(:company, company_profile: { "country" => "UAE" }) }
  let(:key_user) { create(:company_user, company: company, name: "Huda Saleh") }
  let(:colleague) { create(:company_user, company: company) }
  let(:consultant) { create(:consultant_user) }
  let(:admin) { create(:platform_user) }
  let(:engagement) do
    create(:engagement, company: company, key_user: key_user, status: "STAGE_1_PRICING", languages: %w[en ar],
                        lead_consultant: consultant, planned_departments: [{ "name" => "Sales", "count" => 4 }])
  end
  let(:quote) { Pricing::ProposeStage1.call(engagement).quote }

  before { Pricing::Defaults.ensure! }

  def issue! = Pricing::Review.new(actor: admin).approve(quote)
  def show(as: key_user) = get("/api/v1/company/stage1_quote", headers: auth_headers_for(as))
  def body = JSON.parse(response.body)

  def decide(action, by: key_user, **params)
    post "/api/v1/company/stage1_quotes/#{quote.id}/#{action}", params: params, headers: auth_headers_for(by), as: :json
  end

  it "shows nothing while the quote is with the administrator" do
    quote
    show
    expect(body).to eq("quote" => nil)

    decide(:accept, acknowledged: true)
    expect(response).to have_http_status(:not_found)
    expect(quote.reload.status).to eq("PROPOSED")
  end

  it "tells the key user once it is issued, by notification and its email" do
    expect { issue! }.to change(Notification.where(recipient: key_user, notification_type: "stage1_quote_ready"), :count).by(1)
                                                                                                                     .and have_enqueued_job(QuotePdfJob)
    note = Notification.last
    expect(note.body).to include(Pricing::Money.format(quote.total, "AED"))
    expect(note.body).not_to match(INTERNAL)
  end

  it "shows the issued proposal with nothing internal, and notes when it was first opened" do
    issue!
    show

    expect(body["quote"]).to include("status" => "ISSUED", "total" => quote.total.to_s("F"), "participants_included" => 4,
                                     "can_decide" => true)
    expect(body["quote"]["scope"]["what_is_not_included"]).to be_present
    expect(response.body).not_to match(INTERNAL)
    expect(quote.reload.first_viewed_at).to be_present
    expect(quote.events.map(&:event)).to include("viewed")
  end

  it "puts the issued proposal on the dashboard, with nothing internal" do
    stub_request(:get, %r{gotenberg:3000/health}).to_return(status: 200, body: "")
    quote
    get "/api/v1/company/dashboard", headers: auth_headers_for(key_user)
    expect(body["stage1_quote"]).to be_nil

    issue!
    get "/api/v1/company/dashboard", headers: auth_headers_for(key_user)
    expect(body["stage1_quote"]).to include("status" => "ISSUED", "total" => quote.total.to_s("F"), "can_decide" => true)
    expect(body["stage1_quote"].to_json).not_to match(INTERNAL)
  end

  it "lets the key user accept, recorded, which starts Stage 1" do
    issue!
    decide(:accept)
    expect(response).to have_http_status(:unprocessable_entity)

    expect { decide(:accept, acknowledged: true) }.to have_enqueued_mail(PricingMailer, :client_outcome)

    expect(response).to have_http_status(:ok)
    expect(quote.reload).to have_attributes(status: "ACCEPTED", accepted_by: key_user)
    expect(engagement.reload.status).to eq("STAGE_1_ACTIVE")
    expect(engagement.status_history.last).to include("from" => "STAGE_1_PRICING", "to" => "STAGE_1_ACTIVE",
                                                      "by_type" => "CompanyUser", "by_id" => key_user.id)
    expect(Notification.where(recipient: consultant, notification_type: "stage1_quote_decided")).to exist
  end

  it "lets anyone at the company read it, but only the key user decide" do
    issue!
    show(as: colleague)
    expect(body["quote"]["can_decide"]).to be(false)

    decide(:accept, acknowledged: true, by: colleague)
    expect(response).to have_http_status(:forbidden)
    expect(quote.reload.status).to eq("ISSUED")
  end

  it "records a decline and its reason, and tells Mjadi" do
    issue!
    expect { decide(:decline, reason: "Over this quarter's budget") }.to have_enqueued_mail(PricingMailer, :client_outcome)

    expect(quote.reload).to have_attributes(status: "DECLINED", decline_reason: "Over this quarter's budget")
    expect(engagement.reload.status).to eq("STAGE_1_PRICING")
    decide(:accept, acknowledged: true)
    expect(response).to have_http_status(:conflict)
  end

  it "expires an issued proposal past its date, which can then no longer be accepted" do
    issue!
    travel_to(quote.valid_until + 1.day) do
      decide(:accept, acknowledged: true)
      expect(response).to have_http_status(:conflict)
      expect(body["error"]).to include("expired")

      expect { Pricing::Expire.call }.to have_enqueued_mail(PricingMailer, :client_outcome)
      expect(quote.reload.status).to eq("EXPIRED")
      show
      expect(body["quote"]).to include("status" => "EXPIRED", "can_decide" => false)
    end
  end

  it "makes the PDF from the client view only" do
    issue!
    storage = instance_double(Storage::MinioClient, upload: true, download: "%PDF-1.7 quote")
    allow(Storage::MinioClient).to receive(:new).and_return(storage)
    stub_request(:post, %r{gotenberg:3000/forms/chromium/convert/html}).to_return(status: 200, body: "%PDF-1.7 quote")

    html = Pricing::QuotePdf.new(quote).html
    expect(html).to include("Stage 1 proposal", "VAT (5%)", Pricing::Money.format(quote.total, "AED"))
    expect(html.sub(%r{<style>.*</style>}m, "")).not_to match(INTERNAL) # the stylesheet has CSS margins

    get "/api/v1/company/stage1_quotes/#{quote.id}/pdf", headers: auth_headers_for(key_user)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(quote.reload.pdf_storage_key).to eq("quotes/#{company.id}/#{engagement.id}/stage1-v1.pdf")
  end

  it "shows a consultant where it stands and what the client sees, nothing internal" do
    create(:consultant_assignment, consultant_user: consultant, company: company, status: "active")
    quote

    get "/api/v1/consultant/companies/#{company.id}/stage1_quote", headers: auth_headers_for(consultant)
    expect(body).to include("engagement_status" => "STAGE_1_PRICING", "quote" => nil)
    expect(body["latest"]).to include("version" => 1, "status" => "PROPOSED")

    issue!
    get "/api/v1/consultant/companies/#{company.id}/stage1_quote", headers: auth_headers_for(consultant)
    expect(body["quote"]).to include("status" => "ISSUED")
    expect(response.body).not_to match(INTERNAL)
  end

  it "lets Mjadi close an engagement whose price wasn't agreed, withdrawing the open quote" do
    issue!
    post "/api/v1/platform/engagements/#{engagement.id}/close", headers: auth_headers_for(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post "/api/v1/platform/engagements/#{engagement.id}/close", params: { reason: "Client paused the work" },
                                                                headers: auth_headers_for(admin), as: :json
    expect(engagement.reload.status).to eq("CLOSED")
    expect(engagement.status_history.last).to include("reason" => "Client paused the work")
    expect(quote.reload.status).to eq("SUPERSEDED")
  end
end
