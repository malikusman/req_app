# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant company show co-consultant count", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:consultant) { create(:consultant_user) }
  let(:co_consultant) { create(:consultant_user) }

  before do
    create(:consultant_assignment, company: company, consultant_user: consultant)
    create(:consultant_assignment, company: company, consultant_user: co_consultant)
  end

  it "counts other consultants only" do
    get "/api/v1/consultant/companies/#{company.id}", headers: auth_headers_for(consultant)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("company", "co_consultant_count")).to eq(1)
  end
end
