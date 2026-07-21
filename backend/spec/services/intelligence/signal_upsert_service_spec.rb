# frozen_string_literal: true

require "rails_helper"

RSpec.describe Intelligence::SignalUpsertService do
  let(:company) { create(:company) }

  def signal_attrs(evidence_count:, strength: 0.5)
    {
      label: "Manual data entry and spreadsheets",
      signal_type: "manual_process",
      strength: strength,
      evidence_count: evidence_count,
      multimodal_evidence: [],
      source_excerpts: []
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
    expect(first.departments).to include("quality", "finance")
    expect(company.company_signals.where(signal_type: "manual_process").count).to eq(1)
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
