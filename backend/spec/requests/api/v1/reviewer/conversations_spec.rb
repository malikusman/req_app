# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reviewer conversation show", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:reviewer) { create(:reviewer_user) }
  let(:employee) { create(:employee, company: company) }
  let(:conversation) { create(:conversation, employee: employee, company: company, status: "discovery") }

  before do
    create(:reviewer_assignment, company: company, reviewer_user: reviewer)
    create(
      :message,
      conversation: conversation,
      direction: "outbound",
      body: "What tools do you use daily?",
      is_discovery_question: true,
      agent_id: "domain_finance",
      routing_decision: { "action" => "continue", "agent" => "domain_finance", "reason" => "budget remaining" }
    )
  end

  it "returns discovery state and per-message provenance" do
    get "/api/v1/reviewer/companies/#{company.id}/conversations/#{conversation.id}",
        headers: auth_headers_for(reviewer)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["conversation"]["discovery_state"]).to be_a(Hash)
    expect(body["discovery_provenance"].length).to eq(1)
    expect(body["discovery_provenance"].first["agent_id"]).to eq("domain_finance")
    expect(body["messages"].last["agent_id"]).to eq("domain_finance")
  end
end
