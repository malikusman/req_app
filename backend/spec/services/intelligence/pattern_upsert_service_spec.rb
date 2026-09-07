# frozen_string_literal: true

require "rails_helper"

RSpec.describe Intelligence::PatternUpsertService do
  let(:company) { create(:company) }

  def pattern_attrs(confidence:, title: "Approval bottleneck across manual workflows", departments: %w[finance])
    {
      title: title,
      description: "Multiple teams report manual work combined with slow approvals.",
      confidence: confidence,
      linked_signal_ids: [],
      departments: departments
    }
  end

  def stored(title = "Approval bottleneck across manual workflows")
    company.patterns.find_by!(title: title)
  end

  # Patterns had no reconciliation at all, so one detected once lived forever --
  # which would have quietly defeated PatternDetector's cap on cross-department
  # patterns, and more generally kept reporting a pattern whose evidence had gone.
  describe "reconciliation" do
    it "removes a pattern that is no longer detected on a full run" do
      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.8)], reconcile_stale: true)
      expect(company.patterns.count).to eq(1)

      described_class.call(company: company, patterns: [], reconcile_stale: true)

      expect(company.patterns.count).to eq(0)
    end

    # A department-scoped run sees only a slice of the evidence and must not
    # prune what it cannot see.
    it "keeps undetected patterns on a scoped run" do
      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.8)], reconcile_stale: true)

      described_class.call(company: company, patterns: [], reconcile_stale: false)

      expect(company.patterns.count).to eq(1)
    end
  end

  describe "confidence" do
    # `[stored, fresh].max` meant a pattern that peaked once stayed at that
    # confidence forever even as its evidence weakened.
    it "takes the fresh confidence rather than the historical maximum" do
      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.9)])
      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.4)])

      expect(stored.confidence).to be_within(0.001).of(0.4)
    end

    it "lets a pattern fall back to emerging when its evidence weakens" do
      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.9)])
      expect(stored.status).to eq("confirmed")

      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.4)])

      expect(stored.reload.status).to eq("emerging")
    end

    # Nothing is lost by dropping `max`: the peak is recorded, so a pattern that
    # has weakened can still be seen to have been stronger.
    it "records the previous confidence in history when it moves materially" do
      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.9)])
      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.4)])

      expect(stored.confidence_history.map { |h| h["confidence"] }).to include(0.9)
    end

    it "does not record recomputation noise as a move" do
      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.80)])
      before = stored.confidence_history.size

      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.82)])

      expect(stored.reload.confidence_history.size).to eq(before)
    end

    it "caps history so a long-lived company does not grow it without bound" do
      described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.1)])
      50.times { |i| described_class.call(company: company, patterns: [pattern_attrs(confidence: i.even? ? 0.9 : 0.2)]) }

      expect(stored.confidence_history.size).to be <= 40
    end
  end

  it "replaces departments and linked signals rather than accumulating them" do
    described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.8, departments: %w[finance operations])])
    described_class.call(company: company, patterns: [pattern_attrs(confidence: 0.8, departments: %w[finance])])

    expect(stored.departments).to contain_exactly("finance")
  end
end
