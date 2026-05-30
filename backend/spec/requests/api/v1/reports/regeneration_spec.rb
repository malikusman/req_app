# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Report regeneration", type: :request do
  let!(:company) { create(:company, :onboarded) }
  let!(:platform_user) { create(:platform_user) }
  let!(:company_user) { create(:company_user, company: company) }
  let!(:reviewer) { create(:reviewer_user, email: "regen-#{SecureRandom.hex(4)}@example.com") }
  let!(:assignment) { create(:reviewer_assignment, company: company, reviewer_user: reviewer) }
  let!(:source_report) do
    create(:report,
           company: company,
           version: 1,
           status: "ready",
           visibility: "internal_only",
           review_workflow_status: "in_review",
           triggered_by_type: "CompanyUser",
           triggered_by_id: company_user.id)
  end
  let!(:review) { create(:report_review, report: source_report, reviewer_user: reviewer, company: company, status: "in_review") }

  describe "POST /api/v1/platform/companies/:company_id/reports/:id/regenerate" do
    it "creates a new queued report version with source link" do
      post "/api/v1/platform/companies/#{company.id}/reports/#{source_report.id}/regenerate",
           params: { note: "Please incorporate reviewer comments" },
           headers: auth_headers_for(platform_user),
           as: :json

      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      regenerated = Report.find(body.dig("report", "id"))
      expect(regenerated.version).to eq(2)
      expect(regenerated.regeneration_source_report_id).to eq(source_report.id)
      expect(regenerated.regeneration_note).to include("reviewer comments")
      expect(regenerated.visibility).to eq("internal_only")
    end
  end

  describe "POST /api/v1/reviewer/companies/:company_id/reports/:report_id/review/request_regeneration" do
    it "allows assigned reviewer to request regeneration" do
      post "/api/v1/reviewer/companies/#{company.id}/reports/#{source_report.id}/review/request_regeneration",
           params: { note: "Need revised recommendations section" },
           headers: auth_headers_for(reviewer),
           as: :json

      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      expect(body["ok"]).to eq(true)
      regenerated = Report.find(body["report_id"])
      expect(regenerated.regeneration_source_report_id).to eq(source_report.id)
      expect(regenerated.triggered_by_type).to eq("ReviewerUser")
    end
  end
end
