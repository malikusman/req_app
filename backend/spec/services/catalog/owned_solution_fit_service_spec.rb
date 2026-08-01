# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::OwnedSolutionFitService do
  let(:company) { create(:company) }

  before do
    create(:company_signal, company: company, label: "Manual invoice entry", strength: 0.8,
                            departments: ["finance"], signal_type: "manual_process")
    create(:company_signal, company: company, label: "Approval bottleneck", strength: 0.6,
                            departments: ["finance"], signal_type: "approval_bottleneck")
  end

  def owned(name:, description:)
    company.company_systems.create!(
      name: name, kind: "owned_solution", source: "manual", category: "other",
      description: description, normalized_name: CompanySystem.normalize(name)
    )
  end

  it "returns [] when the company has no owned solutions" do
    expect(described_class.call(company: company)).to eq([])
  end

  it "scores fit from description overlap with real signals" do
    owned(name: "InvoiceBot", description: "Automates manual invoice entry and data capture")
    result = described_class.call(company: company)
    fit = result.first
    expect(fit["name"]).to eq("InvoiceBot")
    expect(fit["addresses_signals"]).to include("Manual invoice entry")
    expect(fit["fit_confidence"]).to be > 0.3
    expect(fit["reviewer_endorsed"]).to eq(false)
  end

  it "gives a low floor to a solution that matches nothing" do
    owned(name: "Fleet Tracker", description: "GPS vehicle location for delivery trucks")
    fit = described_class.call(company: company).first
    expect(fit["addresses_signals"]).to be_empty
    expect(fit["fit_confidence"]).to eq(0.3)
  end

  it "surfaces reviewer endorsement" do
    sol = owned(name: "InvoiceBot", description: "Automates manual invoice entry")
    reviewer = create(:reviewer_user, name: "Jane Expert")
    sol.update!(reviewer_endorsed: true, reviewer_note: "Strong fit", reviewer_user: reviewer)
    fit = described_class.call(company: company).first
    expect(fit["reviewer_endorsed"]).to eq(true)
    expect(fit["reviewer_note"]).to eq("Strong fit")
    expect(fit["reviewer_name"]).to eq("Jane Expert")
  end
end
