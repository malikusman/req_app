# frozen_string_literal: true

require "rails_helper"

RSpec.describe Intelligence::SnapshotBuilder do
  let(:company) { create(:company, invited_count: 0) }

  it "exposes uncapped signal_count while keeping top_pain_points limited" do
    6.times { |i| create(:company_signal, company: company, label: "Signal #{i}", strength: i + 1) }

    snapshot = described_class.call(company: company)

    expect(snapshot["signal_count"]).to eq(6)
    expect(snapshot["top_pain_points"].size).to eq(5)
  end

  it "never reports invited below completed" do
    create(:employee, company: company, participation_status: "completed")

    snapshot = described_class.call(company: company)

    expect(snapshot.dig("participation", "completed")).to eq(1)
    expect(snapshot.dig("participation", "invited")).to eq(1)
  end

  it "measures department coverage against the client's plan" do
    create(:engagement, company: company, planned_departments: [{ "name" => "Procurement", "count" => 2 },
                                                                { "name" => "Sales", "count" => "UNKNOWN" }])
    create(:employee, company: company, department: "Procurement", participation_status: "completed")

    coverage = described_class.call(company: company)["department_coverage"].index_by { |d| d["department"] }

    expect(coverage["Procurement"]).to include("completed" => 1, "target" => 2)
    # Planned but not yet counted: shown, with the usual target until a number is given.
    expect(coverage["Sales"]).to include("completed" => 0, "target" => 3)
  end
end
