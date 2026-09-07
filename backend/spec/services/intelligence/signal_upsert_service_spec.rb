# frozen_string_literal: true

require "rails_helper"

RSpec.describe Intelligence::SignalUpsertService do
  let(:company) { create(:company) }

  def signal_attrs(evidence_count:, strength: 0.5, departments: [])
    {
      label: "Manual data entry and spreadsheets",
      signal_type: "manual_process",
      strength: strength,
      evidence_count: evidence_count,
      multimodal_evidence: [],
      source_excerpts: [],
      # SignalExtractor derives this from the evidence that produced the signal.
      departments: departments
    }
  end

  it "keeps the same signal id and replaces evidence_count on re-aggregate (no inflation)" do
    described_class.call(company: company, signals: [signal_attrs(evidence_count: 2, strength: 0.5)], department: "quality")
    first = company.company_signals.find_by!(signal_type: "manual_process")
    first_id = first.id
    expect(first.evidence_count).to eq(2)

    described_class.call(
      company: company,
      signals: [signal_attrs(evidence_count: 3, strength: 0.8)],
      department: "finance",
      reconcile_stale: true
    )
    first.reload

    expect(first.id).to eq(first_id)
    expect(first.evidence_count).to eq(3)
    expect(first.strength).to be >= 0.8
    expect(company.company_signals.where(signal_type: "manual_process").count).to eq(1)
  end

  describe "department attribution" do
    # Departments used to arrive ONLY as a single scalar the caller applied to
    # every signal in the batch, so a signal built entirely from one team's
    # interview got tagged with whatever department the triggering document
    # belonged to -- and the interview path passed none at all, so nothing was
    # ever tagged. See docs/SIGNAL_DEPARTMENT_ATTRIBUTION.md.
    it "takes the departments the signal's own evidence came from" do
      described_class.call(
        company: company,
        signals: [signal_attrs(evidence_count: 5, departments: %w[finance operations])],
        reconcile_stale: true
      )

      signal = company.company_signals.find_by!(signal_type: "manual_process")
      expect(signal.departments).to contain_exactly("finance", "operations")
    end

    # This is what makes PatternDetector's cross-department rule reachable from
    # interview evidence at all.
    it "records a multi-department signal without a caller scalar" do
      described_class.call(
        company: company,
        signals: [signal_attrs(evidence_count: 9, strength: 0.9, departments: %w[finance operations])],
        department: nil,
        reconcile_stale: true
      )

      signal = company.company_signals.find_by!(signal_type: "manual_process")
      expect(signal.departments.size).to be >= 2
    end

    # A full-company run has seen all the evidence, so its derived set is
    # authoritative. Without this a department whose evidence has since gone
    # sticks to the signal forever.
    it "drops a department that no longer has matching evidence on a full run" do
      described_class.call(
        company: company,
        signals: [signal_attrs(evidence_count: 4, departments: %w[finance operations])],
        reconcile_stale: true
      )
      described_class.call(
        company: company,
        signals: [signal_attrs(evidence_count: 4, departments: %w[finance])],
        reconcile_stale: true
      )

      signal = company.company_signals.find_by!(signal_type: "manual_process")
      expect(signal.departments).to contain_exactly("finance")
    end

    # A department-scoped run (a document parse, a media index) only sees a
    # slice of the evidence, so it must not prune what it cannot see.
    it "merges rather than replaces on a department-scoped run" do
      described_class.call(
        company: company,
        signals: [signal_attrs(evidence_count: 4, departments: %w[operations])],
        reconcile_stale: true
      )
      described_class.call(
        company: company,
        signals: [signal_attrs(evidence_count: 4, departments: [])],
        department: "finance"
      )

      signal = company.company_signals.find_by!(signal_type: "manual_process")
      expect(signal.departments).to contain_exactly("operations", "finance")
    end

    it "dedupes departments case-insensitively, keeping first-seen casing" do
      described_class.call(
        company: company,
        signals: [signal_attrs(evidence_count: 4, departments: ["Finance", "finance", " FINANCE "])],
        reconcile_stale: true
      )

      signal = company.company_signals.find_by!(signal_type: "manual_process")
      expect(signal.departments).to eq(["Finance"])
    end
  end

  it "does not inflate evidence_count across identical aggregate passes" do
    attrs = [signal_attrs(evidence_count: 4, strength: 0.6)]
    described_class.call(company: company, signals: attrs, reconcile_stale: true)
    described_class.call(company: company, signals: attrs, reconcile_stale: true)

    signal = company.company_signals.find_by!(signal_type: "manual_process")
    expect(signal.evidence_count).to eq(4)
  end

  it "removes stale signals when reconciling" do
    described_class.call(company: company, signals: [signal_attrs(evidence_count: 2)], reconcile_stale: true)
    expect(company.company_signals.count).to eq(1)

    described_class.call(company: company, signals: [], reconcile_stale: true)
    expect(company.company_signals.count).to eq(0)
  end
end
