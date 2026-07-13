# frozen_string_literal: true

require "rails_helper"

RSpec.describe Intelligence::PatternDetector do
  let(:company) { create(:company) }

  it "returns empty when fewer than two eligible signals exist" do
    create(:company_signal, company: company, signal_type: "approval_bottleneck", strength: 1.0)

    expect(described_class.call(company: company)).to eq([])
  end

  it "detects approval + manual combo when one signal is an anchor and the other meets the floor" do
    create(:company_signal, company: company, signal_type: "approval_bottleneck", strength: 1.0, label: "Approval bottlenecks")
    create(:company_signal, company: company, signal_type: "manual_process", strength: 0.35, label: "Manual data entry")
    create(:company_signal, company: company, signal_type: "tool_dependency", strength: 0.4, label: "Core system")

    patterns = described_class.call(company: company)

    expect(patterns.map { |p| p[:title] }).to include("Approval bottleneck across manual workflows")
  end

  it "does not form a combo from two weak signals" do
    create(:company_signal, company: company, signal_type: "data_silo", strength: 0.35)
    create(:company_signal, company: company, signal_type: "time_sink", strength: 0.35)

    expect(described_class.call(company: company)).to eq([])
  end

  it "detects the same pain across departments on one signal" do
    create(:company_signal, company: company, signal_type: "approval_bottleneck", strength: 0.9,
                            label: "Approval bottlenecks", departments: %w[finance ops])
    create(:company_signal, company: company, signal_type: "tool_dependency", strength: 0.4,
                            label: "Core system", departments: ["finance"])

    patterns = described_class.call(company: company)

    expect(patterns.map { |p| p[:title] }).to include("Approval bottlenecks across departments")
  end
end
