# frozen_string_literal: true

require "rails_helper"

# Settings' "refresh research" reads the website the same way a website change
# does: an engagement company gets pre-fill proposals to confirm, never the old
# unconfirmed summary (Doc 07 §5.4).
RSpec.describe "Company settings: reading the website again", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company, website_url: "https://example-trading.ae") }
  let(:user) { create(:company_user, company: company) }
  let(:path) { "/api/v1/company/settings/organization/web_research" }

  it "reads an engagement company's website for proposals, not for a summary" do
    engagement = create(:engagement, company: company)

    expect {
      post path, headers: auth_headers_for(user)
    }.to have_enqueued_job(WebsitePrefillJob).with(engagement.id)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("queued" => true, "reading" => "prefill")
    expect(CompanyWebResearchJob).not_to have_been_enqueued
    expect(engagement.reload.prefill_status).to eq("pending")
  end

  it "keeps the research summary for a company without an engagement" do
    expect {
      post path, headers: auth_headers_for(user)
    }.to have_enqueued_job(CompanyWebResearchJob).with(company.id, force: true)

    expect(JSON.parse(response.body)).to include("reading" => "research")
  end

  it "needs a website" do
    company.update!(website_url: nil)
    post path, headers: auth_headers_for(user)

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
