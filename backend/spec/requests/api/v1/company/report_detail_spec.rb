# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Company report detail", type: :request do
  let(:company) { create(:company) }
  let(:company_user) { create(:company_user, company: company) }
  let(:consultant) { create(:consultant_user, name: "Dr Amara Okafor", headline: "14 yrs supply-chain ops") }
  let(:headers) { auth_headers_for(company_user) }
  let(:report) do
    company.reports.create!(
      version: 1, status: "ready", visibility: "shared_with_company",
      review_workflow_status: "platform_approved",
      triggered_by_type: "CompanyUser", triggered_by_id: company_user.id,
      storage_key: "reports/#{company.id}/v1/report.pdf", content_type: "application/pdf",
      report_snapshot: { "signals" => [], "executive_summary" => "Machine-written." },
      generated_at: Time.current
    )
  end

  def submitted_review!
    review = ReportReview.create!(
      report: report, consultant_user: consultant, company: company, status: "approved",
      overall_note: "The findings hold up.", opportunity_amount: 450_000,
      opportunity_unit: "AED / year", opportunity_basis: "11-14 day cycle against an 8-day target.",
      submitted_at: Time.current
    )
    review.report_review_findings.create!(
      consultant_user: consultant, finding_type: "executive_conclusion", severity: "material",
      disposition: "endorse", publishable: true, body: "Fix the reconciliation step first."
    )
    review
  end

  # Found by the browser test: the portal hero renders snapshot.expert.opportunity,
  # but the expert layer is applied at RENDER time and lives only on the
  # render-time copy. It reached the PDF and no API response, so the one number an
  # owner most wants could never appear in the portal.
  it "includes the expert layer, which lives only on the render-time snapshot" do
    submitted_review!

    get "/api/v1/company/reports/#{report.id}", headers: headers

    expert = response.parsed_body.dig("report", "report_snapshot", "expert")
    expect(expert.dig("opportunity", "amount")).to eq(450_000)
    expect(expert.dig("opportunity", "consultant")).to eq("Dr Amara Okafor")
    expect(expert.dig("verdict", "body")).to match(/reconciliation/)
    expect(expert["validators"].map { |v| v["name"] }).to eq(["Dr Amara Okafor"])
  end

  # The stored column stays the untouched machine analysis, for the same reason
  # consultant overrides are never written into it.
  it "does not write the expert layer into the stored snapshot" do
    submitted_review!

    get "/api/v1/company/reports/#{report.id}", headers: headers

    expect(report.reload.report_snapshot).not_to have_key("expert")
  end

  it "omits the expert layer when no review has been submitted" do
    get "/api/v1/company/reports/#{report.id}", headers: headers

    expect(response.parsed_body.dig("report", "report_snapshot")).not_to have_key("expert")
  end

  it "lists an artifact per rendering with its page count" do
    report.report_artifacts.create!(
      variant: "exec_brief", storage_key: "reports/brief.pdf", content_type: "application/pdf",
      page_count: 4, generated_at: Time.current
    )

    get "/api/v1/company/reports/#{report.id}", headers: headers

    artifacts = response.parsed_body.dig("report", "artifacts")
    brief = artifacts.find { |a| a["variant"] == "exec_brief" }
    expect(brief["page_count"]).to eq(4)
    expect(brief["orientation"]).to eq("portrait")
  end

  it "refuses a report that has not been shared with the company" do
    report.update!(visibility: "internal_only")

    get "/api/v1/company/reports/#{report.id}", headers: headers

    expect(response).to have_http_status(:forbidden)
  end
end
