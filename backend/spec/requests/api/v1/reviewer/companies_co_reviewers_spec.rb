# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reviewer company show co-reviewer count", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:reviewer) { create(:reviewer_user) }
  let(:co_reviewer) { create(:reviewer_user) }

  before do
    create(:reviewer_assignment, company: company, reviewer_user: reviewer)
    create(:reviewer_assignment, company: company, reviewer_user: co_reviewer)
  end

  it "counts other reviewers only" do
    get "/api/v1/reviewer/companies/#{company.id}", headers: auth_headers_for(reviewer)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("company", "co_reviewer_count")).to eq(1)
  end
end
