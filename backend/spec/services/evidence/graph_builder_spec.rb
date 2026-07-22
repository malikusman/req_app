# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evidence::GraphBuilder do
  let(:company) { create(:company) }
  let!(:employee_a) { create(:employee, company: company, display_name: "Ava", department: "finance") }
  let!(:employee_b) { create(:employee, company: company, display_name: "Ben", department: "finance") }
  let!(:employee_c) { create(:employee, company: company, display_name: "Cara", department: "ops") }

  let!(:signal) do
    create(
      :company_signal,
      company: company,
      label: "Manual re-entry",
      metadata: {
        "source_excerpts" => [
          { "employee_id" => employee_a.id, "conversation_id" => 1, "excerpt" => "We retype invoices into SAP" },
          { "employee_id" => employee_b.id, "conversation_id" => 2, "excerpt" => "Same data entered twice" }
        ]
      }
    )
  end

  let!(:pattern) do
    Pattern.create!(
      company: company,
      title: "Finance handoff friction",
      description: "Approvals stall between teams",
      confidence: 0.8,
      status: "confirmed",
      departments: %w[finance],
      linked_signal_ids: [signal.id],
      first_seen_at: Time.current,
      last_updated_at: Time.current
    )
  end

  let!(:recommendation) do
    Recommendation.create!(
      company: company,
      title: "Automate invoice capture",
      description: "Reduce re-entry",
      status: "published",
      priority: "high",
      related_signal_ids: [signal.id],
      related_pattern_ids: [pattern.id]
    )
  end

  it "wires signal↔employee, signal↔pattern, recommendation links, and employee clusters" do
    graph = described_class.call(company: company)

    expect(graph[:nodes]).to include(
      hash_including(type: "employee", id: employee_a.id, label: "Ava")
    )

    extracted = graph[:edges].select { |e| e[:type] == "extracted_from" }
    expect(extracted.size).to eq(2)
    expect(extracted.map { |e| e.dig(:to, :id) }).to contain_exactly(employee_a.id, employee_b.id)
    expect(extracted.first[:excerpt]).to be_present

    expect(graph[:edges]).to include(
      hash_including(
        type: "aggregates_into",
        from: { type: "signal", id: signal.id },
        to: { type: "pattern", id: pattern.id }
      )
    )

    expect(graph[:edges]).to include(
      hash_including(
        type: "supports",
        from: { type: "pattern", id: pattern.id },
        to: { type: "recommendation", id: recommendation.id }
      )
    )
    expect(graph[:edges]).to include(
      hash_including(
        type: "derived_from",
        from: { type: "recommendation", id: recommendation.id },
        to: { type: "signal", id: signal.id }
      )
    )

    shared = graph[:edges].find { |e| e[:type] == "shares_signal" }
    expect(shared).to be_present
    expect([shared.dig(:from, :id), shared.dig(:to, :id)]).to contain_exactly(employee_a.id, employee_b.id)
    expect(shared[:weight]).to eq(1)

    same_dept = graph[:edges].select { |e| e[:type] == "same_department" }
    # Ava+Ben already share a signal, so same_department is skipped for that pair;
    # Cara alone in ops → no same_department edges required.
    expect(same_dept).to all(satisfy { |e| e.dig(:from, :type) == "employee" })

    ava = graph[:nodes].find { |n| n[:type] == "employee" && n[:id] == employee_a.id }
    expect(ava[:evidence_count]).to eq(1)

    expect(graph[:coverage][:supported_edges]).to be >= 3
    expect(graph[:coverage][:shares_signal_edges]).to eq(1)
    expect(graph[:coverage][:signals_linked]).to eq(1)
  end
end
