# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::ExpertConsultants", type: :request do
  before do
    ConsultantExperience.delete_all
    ConsultantUser.delete_all
  end

  let!(:company) { create(:company, :onboarded) }
  let!(:company_user) { create(:company_user, company: company) }
  let!(:consultant) { create(:consultant_user, :published_profile) }
  let!(:assignment) { create(:consultant_assignment, company: company, consultant_user: consultant) }

  describe "GET /api/v1/company/expert_consultants" do
    it "returns published assigned consultants only" do
      draft = create(:consultant_user, headline: "Draft only")
      create(:consultant_assignment, company: company, consultant_user: draft)

      get "/api/v1/company/expert_consultants", headers: auth_headers_for(company_user)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["expert_consultants"].map { |r| r["id"] }
      expect(ids).to eq([consultant.id])
    end
  end
end
