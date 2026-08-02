# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reviewer catalog add-from-catalog", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:reviewer) { create(:reviewer_user) }
  let!(:first_party) do
    SolutionCatalogEntry.create!(name: "Worktruth AP Copilot", category: "automation", active: true, first_party: true)
  end
  let!(:third_party) do
    SolutionCatalogEntry.create!(name: "Zapier", category: "automation", active: true, first_party: false)
  end

  before { create(:reviewer_assignment, company: company, reviewer_user: reviewer) }

  it "lists available catalog products (first-party first) not yet matched" do
    get "/api/v1/reviewer/companies/#{company.id}/catalog/available", headers: auth_headers_for(reviewer)
    expect(response).to have_http_status(:ok)
    names = JSON.parse(response.body)["solutions"].map { |s| s["name"] }
    expect(names).to include("Worktruth AP Copilot", "Zapier")
    expect(names.first).to eq("Worktruth AP Copilot") # first_party ordered first
  end

  it "adds a catalog product to the company with reviewer attribution" do
    expect do
      post "/api/v1/reviewer/companies/#{company.id}/catalog/add",
           params: { solution_catalog_entry_id: first_party.id, why_it_fits: "Directly automates AP." },
           headers: auth_headers_for(reviewer)
    end.to change { CompanyCatalogMatch.count }.by(1)

    expect(response).to have_http_status(:created)
    match = CompanyCatalogMatch.last
    expect(match.solution_catalog_entry).to eq(first_party)
    expect(match.added_by_reviewer).to eq(reviewer)
    expect(match.why_it_fits).to eq("Directly automates AP.")
  end

  it "excludes an already-matched product from the available pool" do
    CompanyCatalogMatch.create!(company: company, solution_catalog_entry: third_party, score: 0.5, matched_at: Time.current)
    get "/api/v1/reviewer/companies/#{company.id}/catalog/available", headers: auth_headers_for(reviewer)
    names = JSON.parse(response.body)["solutions"].map { |s| s["name"] }
    expect(names).to include("Worktruth AP Copilot")
    expect(names).not_to include("Zapier")
  end

  it "blocks adding for an unassigned company" do
    other = create(:company, :onboarded)
    post "/api/v1/reviewer/companies/#{other.id}/catalog/add",
         params: { solution_catalog_entry_id: first_party.id }, headers: auth_headers_for(reviewer)
    expect(response).to have_http_status(:not_found)
  end
end
