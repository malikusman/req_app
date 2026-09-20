# frozen_string_literal: true

require "rails_helper"

# "Send the board the brief" and "share everything" are different acts. A share
# link is scoped to one rendering, and the copied link says which.
RSpec.describe Reports::ShareLinkService do
  let(:company) { create(:company) }
  let(:report) do
    company.reports.create!(
      version: 1, status: "ready", visibility: "shared_with_company",
      triggered_by_type: "CompanyUser", triggered_by_id: 1,
      storage_key: "reports/#{company.id}/v1/report.pdf", content_type: "application/pdf",
      report_snapshot: { "signals" => [] }, generated_at: Time.current
    )
  end

  before do
    report.report_artifacts.create!(
      variant: "exec_brief", storage_key: "reports/#{company.id}/v1/exec_brief.pdf",
      content_type: "application/pdf", page_count: 4, generated_at: Time.current
    )
    allow(NotificationService).to receive(:notify_report_shared)
  end

  it "mints separate links for the brief and the full report" do
    full = described_class.create!(report: report, variant: "full")
    brief = described_class.create!(report: report, variant: "exec_brief")

    expect(full[:share_token]).not_to eq(brief[:share_token])
    expect(brief[:variant_label]).to eq("Executive brief")
    expect(report.report_shares.live.pluck(:variant)).to match_array(%w[full exec_brief])
  end

  # Links already in a client's inbox must keep resolving.
  it "still writes the legacy share_token for the full variant" do
    result = described_class.create!(report: report, variant: "full")

    expect(report.reload.share_token).to eq(result[:share_token])
    expect(report).to be_share_active
  end

  it "does not touch the legacy token when sharing only the brief" do
    described_class.create!(report: report, variant: "exec_brief")

    expect(report.reload.share_token).to be_nil
  end

  # Resharing should mean "replace", not "leave two live URLs for one rendering".
  it "revokes the previous link for that variant when reshared" do
    first = described_class.create!(report: report, variant: "exec_brief")
    described_class.create!(report: report, variant: "exec_brief")

    expect(report.report_shares.find_by(token: first[:share_token])).not_to be_active
    expect(report.report_shares.live.where(variant: "exec_brief").count).to eq(1)
  end

  it "refuses to share a rendering that was never produced" do
    report.artifact_for("exec_brief").update!(storage_key: nil)

    expect { described_class.create!(report: report, variant: "exec_brief") }
      .to raise_error(ArgumentError, /has not been rendered/)
  end

  it "refuses to share a report the company cannot see yet" do
    report.update!(visibility: "internal_only")

    expect { described_class.create!(report: report, variant: "full") }
      .to raise_error(ArgumentError, /not shareable/)
  end

  describe ".revoke!" do
    before do
      described_class.create!(report: report, variant: "full")
      described_class.create!(report: report, variant: "exec_brief")
    end

    it "revokes one variant and leaves the other live" do
      described_class.revoke!(report: report, variant: "exec_brief")

      expect(report.report_shares.live.pluck(:variant)).to eq(%w[full])
      expect(report.reload.share_token).to be_present
    end

    it "revokes everything, including the legacy token, when given no variant" do
      described_class.revoke!(report: report)

      expect(report.report_shares.live).to be_empty
      expect(report.reload.share_token).to be_nil
    end
  end
end
