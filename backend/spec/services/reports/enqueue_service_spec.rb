# frozen_string_literal: true

require "rails_helper"

# Generation had no reachable entry point at all before this: the company
# endpoint was refused by policy, the consultant's refresh had no caller, and the
# platform had nothing. Every report came from a rake task.
RSpec.describe Reports::EnqueueService do
  let(:company) { create(:company) }
  let(:consultant) { create(:consultant_user) }

  before { allow(GenerateReportJob).to receive(:perform_later) }

  def existing_report(generated_at: 2.days.ago)
    company.reports.create!(version: 1, status: "ready", visibility: "shared_with_company",
                            review_workflow_status: "platform_approved",
                            triggered_by_type: "CompanyUser", triggered_by_id: 1,
                            report_snapshot: { "signals" => [] },
                            generated_at: generated_at)
  end

  describe "the first report for a company" do
    it "is always allowed — there is nothing for it to be stale against" do
      company.update!(intelligence_updated_at: 3.days.ago)

      result = described_class.call(company: company, triggered_by: consultant)

      expect(result[:report].version).to eq(1)
      expect(result[:first]).to be true
      expect(GenerateReportJob).to have_received(:perform_later).with(result[:report].id)
    end

    it "is attributed to whoever triggered it" do
      result = described_class.call(company: company, triggered_by: consultant)

      expect(result[:report].triggered_by_type).to eq("ConsultantUser")
      expect(result[:report].triggered_by_id).to eq(consultant.id)
    end

    it "is attributed to a platform user when the platform generates it" do
      operator = create(:platform_user)

      result = described_class.call(company: company, triggered_by: operator)

      expect(result[:report].triggered_by_type).to eq("PlatformUser")
      expect(result[:report].triggered_by_id).to eq(operator.id)
    end
  end

  describe "a later version" do
    it "mints the next version and links the previous one for the delta" do
      previous = existing_report
      company.update!(intelligence_updated_at: 1.hour.ago)

      result = described_class.call(company: company, triggered_by: consultant)

      expect(result[:report].version).to eq(2)
      expect(result[:report].previous_report).to eq(previous)
      expect(result[:first]).to be false
    end

    # A consultant regenerating does not get to skip their own review, and the
    # client keeps the version they already have until this one is approved.
    it "is held back from the company" do
      existing_report
      company.update!(intelligence_updated_at: 1.hour.ago)

      result = described_class.call(company: company, triggered_by: consultant)

      expect(result[:report].visibility).to eq("internal_only")
    end

    it "refuses when nothing has changed, rather than burning a version number" do
      existing_report
      company.update!(intelligence_updated_at: 3.days.ago)

      expect { described_class.call(company: company, triggered_by: consultant) }
        .to raise_error(described_class::NotStale, /No new evidence/)
      expect(company.reports.count).to eq(1)
    end

    # The staleness check is a hint, not a veto: a consultant re-cutting after
    # editing sections has a reason the system cannot see.
    it "generates anyway when the consultant forces it" do
      existing_report
      company.update!(intelligence_updated_at: 3.days.ago)

      result = described_class.call(company: company, triggered_by: consultant, force: true)

      expect(result[:report].version).to eq(2)
      expect(result[:stale]).to be false
    end
  end

  it "refuses while another version is already generating, as a distinct error" do
    existing_report
    company.update!(intelligence_updated_at: 1.hour.ago)
    company.reports.create!(version: 9, status: "generating", visibility: "internal_only",
                            triggered_by_type: "CompanyUser", triggered_by_id: 1)

    expect { described_class.call(company: company, triggered_by: consultant) }
      .to raise_error(described_class::Busy, /already generating/)
  end

  it "does not let force stampede a run that is already in flight" do
    company.reports.create!(version: 1, status: "queued", visibility: "internal_only",
                            triggered_by_type: "CompanyUser", triggered_by_id: 1)

    expect { described_class.call(company: company, triggered_by: consultant, force: true) }
      .to raise_error(described_class::Busy)
  end

  # A worker that died mid-run leaves a report saying "generating" forever. Left
  # unbounded, that locks the company out of report generation permanently, with
  # "already generating" as the only explanation. One such row was sitting in the
  # database six weeks old.
  it "ignores a stuck run that is far older than any real one" do
    company.reports.create!(version: 1, status: "generating", visibility: "internal_only",
                            triggered_by_type: "CompanyUser", triggered_by_id: 1,
                            created_at: 3.days.ago)

    # force isolates the in-flight window from the staleness check — a stuck row
    # is still the latest report, so an unforced call would stop on NotStale.
    result = described_class.call(company: company, triggered_by: consultant, force: true)

    expect(result[:report].version).to eq(2)
  end

  # A failed run must not wedge the company out of ever generating again.
  it "ignores a failed report when deciding whether one is in flight" do
    company.reports.create!(version: 1, status: "failed", visibility: "internal_only",
                            triggered_by_type: "CompanyUser", triggered_by_id: 1)

    result = described_class.call(company: company, triggered_by: consultant, force: true)

    expect(result[:report].version).to eq(2)
  end
end
