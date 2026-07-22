# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reviewer report findings evidence refs", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:reviewer) { create(:reviewer_user) }
  let!(:report) { create(:report, :ready, company: company) }
  let!(:review) { create(:report_review, report: report, reviewer_user: reviewer, company: company) }
  let!(:signal) { create(:company_signal, company: company, label: "Manual re-entry") }
  let!(:pattern) do
    Pattern.create!(
      company: company,
      title: "Handoff friction",
      description: "Work stalls between teams",
      confidence: 0.8,
      status: "confirmed",
      departments: ["finance"],
      linked_signal_ids: [signal.id],
      first_seen_at: Time.current,
      last_updated_at: Time.current
    )
  end

  before { create(:reviewer_assignment, company: company, reviewer_user: reviewer) }

  it "keeps only company-owned signal/pattern refs" do
    post "/api/v1/reviewer/companies/#{company.id}/reports/#{report.id}/review/findings",
         params: {
           finding: {
             finding_type: "risk",
             severity: "info",
             body: "Linked to real evidence",
             publishable: true,
             evidence_refs: ["signal:#{signal.id}", "pattern:#{pattern.id}", "signal:999999", "notes from call"]
           }
         },
         headers: auth_headers_for(reviewer),
         as: :json

    expect(response).to have_http_status(:created)
    refs = JSON.parse(response.body).dig("finding", "evidence_refs")
    expect(refs).to contain_exactly("signal:#{signal.id}", "pattern:#{pattern.id}")
  end
end
