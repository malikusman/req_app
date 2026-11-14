# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform approval runs the report checks", type: :request do
  let(:admin) { create(:platform_user) }
  let(:headers) { auth_headers_for(admin) }
  let(:company) { create(:company, :onboarded) }
  let(:report) do
    create(:report, company: company, review_workflow_status: "reviews_complete", content_type: "application/pdf",
                    report_snapshot: { "company" => { "name" => "Acme" } })
  end
  let(:blocking) { [{ code: "payroll_language", severity: "block", section: nil, message: "Converts time into money" }] }

  def approve(params = {})
    post "/api/v1/platform/companies/#{company.id}/reports/#{report.id}/approve", params: params, headers: headers
  end

  before { allow(NotificationService).to receive(:notify_report_ready) }

  it "refuses approval while a blocking check fails, and says which" do
    allow(Reports::Critic).to receive(:call).and_return(blocking)

    approve

    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body["checks"].first["code"]).to eq("payroll_language")
    expect(report.reload.review_workflow_status).to eq("reviews_complete")
  end

  it "approves over a blocking check only with a reason, and records it" do
    allow(Reports::Critic).to receive(:call).and_return(blocking)

    expect { approve(override_reason: "The client's own wording, quoted in their goals") }
      .to change { PlatformAuditLog.where(action: "report_checks_overridden").count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(report.reload.review_workflow_status).to eq("platform_approved")
  end

  it "approves when only warnings remain" do
    allow(Reports::Critic).to receive(:call).and_return([{ code: "few_hours", severity: "warn", section: nil, message: "x" }])
    approve
    expect(response).to have_http_status(:ok)
  end

  it "lists the checks without approving" do
    allow(Reports::Critic).to receive(:call).and_return(blocking)
    get "/api/v1/platform/companies/#{company.id}/reports/#{report.id}/checks", headers: headers
    expect(JSON.parse(response.body)["checks"].size).to eq(1)
    expect(report.reload.review_workflow_status).to eq("reviews_complete")
  end
end
