# frozen_string_literal: true

require "rails_helper"

# Who is allowed to put a report on the queue, across all three portals.
#
# This existed in no portal at all until now: the company endpoint was refused by
# policy behind a button that could only return Forbidden, the consultant's
# refresh action had no caller, and the platform had nothing. Reports were made
# by rake task.
RSpec.describe "Report generation", type: :request do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }
  let(:operator) { create(:platform_user) }

  before { allow(GenerateReportJob).to receive(:perform_later) }

  describe "the consultant" do
    let!(:assignment) { create(:consultant_assignment, consultant_user: consultant, company: company) }
    let(:path) { "/api/v1/consultant/companies/#{company.id}/reports" }

    it "generates a first report for a company it is assigned to" do
      post path, headers: auth_headers_for(consultant)

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body["first"]).to be true
      expect(company.reports.reload.count).to eq(1)
      expect(company.reports.first.triggered_by_type).to eq("ConsultantUser")
    end

    # Held at internal_only: a consultant generating does not skip their own
    # review, and nothing reaches the client without platform approval.
    it "does not ship it to the client" do
      post path, headers: auth_headers_for(consultant)

      expect(company.reports.reload.first.visibility).to eq("internal_only")
    end

    it "cannot generate for a company it is not assigned to" do
      other = create(:company)

      post "/api/v1/consultant/companies/#{other.id}/reports", headers: auth_headers_for(consultant)

      expect(response).to have_http_status(:not_found)
      expect(other.reports.reload.count).to eq(0)
    end

    context "when a report already exists and nothing has changed" do
      before do
        company.reports.create!(version: 1, status: "ready", visibility: "shared_with_company",
                                triggered_by_type: "ConsultantUser", triggered_by_id: consultant.id,
                                generated_at: 1.hour.ago)
        company.update!(intelligence_updated_at: 2.days.ago)
      end

      it "refuses, and says the refusal can be overridden" do
        post path, headers: auth_headers_for(consultant)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["forceable"]).to be true
      end

      it "generates anyway when forced" do
        post path, params: { force: true }, headers: auth_headers_for(consultant)

        expect(response).to have_http_status(:accepted)
        expect(company.reports.reload.count).to eq(2)
      end
    end

    it "returns a conflict rather than a second run while one is generating" do
      company.reports.create!(version: 1, status: "generating", visibility: "internal_only",
                              triggered_by_type: "ConsultantUser", triggered_by_id: consultant.id)

      post path, headers: auth_headers_for(consultant)

      expect(response).to have_http_status(:conflict)
    end
  end

  describe "the platform operator" do
    let(:path) { "/api/v1/platform/companies/#{company.id}/reports" }

    # The fallback that matters: a company with no consultant assigned has nobody
    # who could generate for it, and would otherwise never get a report at all.
    it "generates for a company with no consultant assigned" do
      expect(company.consultant_assignments).to be_empty

      post path, headers: auth_headers_for(operator)

      expect(response).to have_http_status(:accepted)
      expect(company.reports.reload.first.triggered_by_type).to eq("PlatformUser")
    end

    it "records the action in the audit log" do
      expect { post path, headers: auth_headers_for(operator) }
        .to change { PlatformAuditLog.where(action: "report_generation_started").count }.by(1)
    end
  end

  describe "the company" do
    let(:company_admin) { create(:company_user, company: company, role: "company_admin") }

    # A client does not commission their own deliverable. The portal used to ship
    # a button for this that could only ever return Forbidden.
    it "has no route to generate at all" do
      post "/api/v1/company/reports", headers: auth_headers_for(company_admin)

      expect(response).to have_http_status(:not_found)
      expect(company.reports.reload.count).to eq(0)
    end
  end
end
