# frozen_string_literal: true

require "rails_helper"

# Evidence does not stop arriving when a report is reviewed. Until now the only
# way to fold new signals in was for the COMPANY to click Generate, which is
# backwards -- the consultant is the one who knows whether new evidence changes
# the advice.
RSpec.describe Reports::ConsultantRefreshService do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }
  let!(:report) do
    company.reports.create!(version: 1, status: "ready", visibility: "shared_with_company",
                            review_workflow_status: "platform_approved",
                            triggered_by_type: "CompanyUser", triggered_by_id: 1,
                            report_snapshot: { "signals" => [] },
                            generated_at: 2.days.ago)
  end

  before { allow(GenerateReportJob).to receive(:perform_later) }

  context "when new intelligence has landed since the report was generated" do
    before { company.update!(intelligence_updated_at: 1.hour.ago) }

    it "mints the next version attributed to the consultant" do
      result = described_class.call(report: report, consultant_user: consultant)

      expect(result[:report].version).to eq(2)
      expect(result[:report].triggered_by_type).to eq("ConsultantUser")
      expect(result[:report].triggered_by_id).to eq(consultant.id)
      expect(GenerateReportJob).to have_received(:perform_later).with(result[:report].id)
    end

    it "links the previous version so the delta can state what changed" do
      result = described_class.call(report: report, consultant_user: consultant)

      expect(result[:report].previous_report).to eq(report)
    end

    # A consultant refreshing a report does not get to skip their own review.
    it "holds the new version back from the company" do
      result = described_class.call(report: report, consultant_user: consultant)

      expect(result[:report].visibility).to eq("internal_only")
      expect(result[:report].review_workflow_status).to eq("not_required")
    end
  end

  it "refuses when nothing has changed, rather than burning a version number" do
    company.update!(intelligence_updated_at: 3.days.ago)

    expect { described_class.call(report: report, consultant_user: consultant) }
      .to raise_error(described_class::NotStale, /No new evidence/)
    expect(company.reports.count).to eq(1)
  end

  it "refreshes anyway when explicitly forced" do
    company.update!(intelligence_updated_at: 3.days.ago)

    result = described_class.call(report: report, consultant_user: consultant, force: true)

    expect(result[:report].version).to eq(2)
    expect(result[:stale]).to be false
  end

  it "refuses while another version is already generating" do
    company.update!(intelligence_updated_at: 1.hour.ago)
    company.reports.create!(version: 9, status: "generating", visibility: "internal_only",
                            triggered_by_type: "CompanyUser", triggered_by_id: 1)

    expect { described_class.call(report: report, consultant_user: consultant) }
      .to raise_error(described_class::NotStale, /already generating/)
  end
end
