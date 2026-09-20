# frozen_string_literal: true

require "rails_helper"

# The opportunity figure was collected in the review workspace, reached the
# company dashboard, and appeared in NO pdf. This is the layer that carries it
# (and the consultant's own conclusion) into both renderings.
RSpec.describe Reports::ExpertLayer do
  let(:company) { create(:company) }
  let(:consultant) do
    create(:consultant_user, name: "Dr Amara Okafor", headline: "14 yrs supply-chain ops",
                             expertise_tags: %w[procurement logistics])
  end
  let(:report) do
    company.reports.create!(version: 1, status: "ready", visibility: "internal_only",
                            triggered_by_type: "CompanyUser", triggered_by_id: 1,
                            report_snapshot: { "signals" => [] }, generated_at: Time.current)
  end

  def review!(consultant_user: consultant, amount: nil, unit: nil, basis: nil, submitted: true, conclusion: true)
    review = ReportReview.create!(
      report: report, consultant_user: consultant_user, company: company,
      status: "approved", overall_note: "Findings hold up.",
      opportunity_amount: amount, opportunity_unit: unit, opportunity_basis: basis,
      submitted_at: submitted ? Time.current : nil
    )
    if conclusion
      review.report_review_findings.create!(
        consultant_user: consultant_user, finding_type: "executive_conclusion",
        severity: "material", disposition: "endorse", publishable: true,
        body: "Fix the PO reconciliation step first; everything else follows."
      )
    end
    review
  end

  it "returns nil when no review has been submitted" do
    review!(submitted: false)

    expect(described_class.call(report: report)).to be_nil
  end

  it "carries the opportunity amount, unit, basis and who sized it" do
    review!(amount: 450_000, unit: "AED / year", basis: "11 days of AP float against an 8-day target.")

    opportunity = described_class.call(report: report)["opportunity"]

    expect(opportunity["amount"]).to eq(450_000)
    expect(opportunity["unit"]).to eq("AED / year")
    expect(opportunity["basis"]).to match(/8-day target/)
    expect(opportunity["consultant"]).to eq("Dr Amara Okafor")
    expect(opportunity["consultant_credential"]).to include("14 yrs supply-chain ops")
  end

  # Averaging figures that were reasoned differently would invent a number no
  # expert actually stands behind.
  it "leads with the best-evidenced figure and counts the corroborating ones" do
    review!(amount: 200_000, unit: "AED / year")
    review!(consultant_user: create(:consultant_user, name: "Sam Reviewer"), amount: 450_000, unit: "AED / year")

    opportunity = described_class.call(report: report)["opportunity"]

    expect(opportunity["amount"]).to eq(450_000)
    expect(opportunity["consultant"]).to eq("Sam Reviewer")
    expect(opportunity["corroborated_by"]).to eq(1)
  end

  it "omits the opportunity entirely when nobody sized one" do
    review!

    expect(described_class.call(report: report)).not_to have_key("opportunity")
  end

  it "surfaces the publishable executive conclusion as the verdict" do
    review!

    verdict = described_class.call(report: report)["verdict"]

    expect(verdict["body"]).to match(/PO reconciliation/)
    expect(verdict["consultant"]).to eq("Dr Amara Okafor")
    expect(verdict["overall_note"]).to eq("Findings hold up.")
  end

  it "lists every validator with their credential" do
    review!
    review!(consultant_user: create(:consultant_user, name: "Sam Reviewer", years_experience: 9))

    validators = described_class.call(report: report)["validators"]

    expect(validators.map { |v| v["name"] }).to contain_exactly("Dr Amara Okafor", "Sam Reviewer")
    expect(validators.find { |v| v["name"] == "Sam Reviewer" }["credential"]).to include("9+ years")
  end
end
