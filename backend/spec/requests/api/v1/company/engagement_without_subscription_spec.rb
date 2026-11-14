# frozen_string_literal: true

require "rails_helper"

# Companies set up as engagements have no subscription at all. Screens that
# once read the subscription's conversation cap must still work for them.
RSpec.describe "A company on an engagement, with no subscription", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:company_user, company: company) }

  before do
    # The dashboard reports the health of the agent and PDF services.
    stub_request(:get, %r{http://langgraph:8000/health}).to_return(status: 200, body: '{"status":"ok"}')
    stub_request(:get, %r{http://gotenberg:3000/health}).to_return(status: 200, body: "")
    company.subscription.destroy!
    create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY",
                        planned_departments: [{ "name" => "Sales", "count" => "UNKNOWN" }],
                        onboarding_submitted_at: Time.current)
  end

  it "loads the dashboard, with no conversation cap and the onboarding state" do
    get "/api/v1/company/dashboard", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["usage"]).to include("conversation_limit" => nil, "limit_reached" => false)
    expect(body["engagement_status"]).to eq("KEY_PERSON_DISCOVERY")
    expect(body["onboarding_submitted_at"]).to be_present
    expect(body["planned_participant_count"]).to be_nil
    # Nothing uploaded, so nothing is "being analysed".
    expect(body.dig("intel_counts", "processing_documents")).to eq(0)
  end

  it "counts only documents still being worked on as processing, not failed ones" do
    %w[pending processing failed ready].each_with_index do |status, i|
      company.documents.create!(filename: "doc#{i}.pdf", storage_key: "k#{i}", source: "company_portal_upload",
                                status: status)
    end

    get "/api/v1/company/dashboard", headers: auth_headers_for(user)

    expect(JSON.parse(response.body)["intel_counts"]).to include("processing_documents" => 2, "ready_documents" => 1)
  end

  it "loads the signed-in user" do
    get "/api/v1/company/me", headers: auth_headers_for(user)
    expect(response).to have_http_status(:ok)
  end
end
