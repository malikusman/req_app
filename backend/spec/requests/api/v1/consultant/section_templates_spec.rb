# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant section library", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:consultant) { create(:consultant_user) }
  let!(:assignment) { create(:consultant_assignment, company: company, consultant_user: consultant, status: "active") }

  it "offers the Stage 1 templates, and not the implementation plan" do
    get "/api/v1/consultant/companies/#{company.id}/section_templates", headers: auth_headers_for(consultant)

    expect(response).to have_http_status(:ok)
    keys = JSON.parse(response.body)["templates"].map { |t| t["key"] }
    expect(keys).to include("expert_conclusion", "assumptions_limitations", "next_steps")
    expect(keys).not_to include("implementation")
  end
end
