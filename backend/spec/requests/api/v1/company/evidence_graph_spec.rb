# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Company evidence graph", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:user) { create(:company_user, company: company) }
  let!(:employee) { create(:employee, company: company, display_name: "Ava") }

  it "returns the company evidence graph" do
    get "/api/v1/company/evidence_graph", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["graph"]["nodes"]).to include(
      hash_including("type" => "employee", "id" => employee.id, "label" => "Ava")
    )
    expect(body["graph"]["coverage"]).to include("supported_edges", "shares_signal_edges")
  end
end
