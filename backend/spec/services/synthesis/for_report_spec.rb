# frozen_string_literal: true

require "rails_helper"

# Doc 10 §10.3 and Doc 15 §4.4, §4.5, §8.4, C7, C11: the report counts confirmed
# shared work once and every total still reconciles; it takes from synthesis
# only what a consultant approved; leadership's view appears only as a material
# difference, worded as one; and with nothing approved the report is unchanged.
RSpec.describe "Synthesis in the report" do
  let(:company) { create(:company, :onboarded) }
  let!(:engagement) { create(:engagement, company: company) }
  let(:consultant) { create(:consultant_user) }
  let(:buyer) { create(:employee, company: company, role_title: "Buyer", department: "Procurement") }

  before do
    company.update!(settings: company.settings.merge("report_small_roles" => "show"))
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
  end

  # One person's purchase-order chase, named twice with the same figures.
  let!(:orders) do
    synthesis_finding(company: company, employee: buyer, role: "Buyer", department: "Procurement", title: "Purchase orders",
                      what_happens_now: "Raise purchase orders and chase suppliers", hours: [120, 180], status: "approved")
  end
  let!(:chase) do
    synthesis_finding(company: company, employee: buyer, role: "Buyer", department: "Procurement", title: "Supplier follow-up",
                      what_happens_now: "Chase suppliers about purchase orders", hours: [120, 180], status: "approved",
                      evidence: { "possible_duplicate_of" => orders.id })
  end
  let!(:quotes) do
    synthesis_finding(company: company, role: "Sales Coordinator", department: "Sales", title: "Quotations",
                      what_happens_now: "Prepare quotations from the price list", hours: [100, 150], status: "approved")
  end

  def synthesise!
    run = SynthesisRun.create!(company: company, engagement: engagement, trigger: "MANUAL", requested_at: Time.current,
                               version: (SynthesisRun.where(engagement: engagement).maximum(:version) || 0) + 1)
    Synthesis::Run.call(run, client: Synthesis::ScriptedClient.new)
  end

  def decide(action, subject, **details)
    Synthesis::Decide.call(engagement: engagement, actor: consultant, action: action, subject_id: subject&.id,
                           rationale: "Checked", params: details)
  end

  def view = Findings::ForReport.call(company: company)
  def rows(v = view) = v["departments"].flat_map { |d| d["roles"].flat_map { |r| r["findings"] } }

  it "leaves the report as it was until a consultant approves anything" do
    synthesise!
    snapshot = Reports::SnapshotBuilder.call(company: company, delta: {})

    expect(snapshot["synthesis"]).to eq({})
    expect(snapshot.dig("findings", "totals")).to include("hours_min" => 340, "hours_max" => 510)
    expect(rows(snapshot["findings"]).map { |r| r["counted_in"] }).to all(be_nil)
  end

  it "counts one execution named twice once, once the consultant confirms it, and every total reconciles" do
    synthesise!
    decide("APPROVE_CLUSTER", SynthesisCluster.current.sole)

    totals = view["totals"]
    expect(totals).to include("hours_min" => 220, "hours_max" => 330, "findings" => 3)
    set_aside = rows.find { |r| r["counted_in"] }
    expect(set_aside["counted_in"]["id"]).to eq(chase.id).or eq(orders.id)
    expect(set_aside["hours_min"]).to eq(120) # its own figures stay on its row

    snapshot = Reports::SnapshotBuilder.call(company: company, delta: {})
    report = create(:report, company: company, report_snapshot: snapshot, generated_at: 1.minute.ago)
    allow(Reports::RegenerateWithReviewService).to receive(:render_html).and_return("<html><body></body></html>")
    expect(Reports::Critic.call(report: report).map { |c| c[:code] }).not_to include("unreconciled_totals")
  end

  it "points each finding of shared work to where else it appears" do
    sales_quotes = synthesis_finding(company: company, role: "Buyer", department: "Sales", title: "Supplier follow-up",
                                     what_happens_now: "Chase suppliers about purchase orders", hours: [40, 60],
                                     status: "approved")
    synthesise!
    SynthesisCluster.current.each { |c| decide("APPROVE_CLUSTER", c) }

    procurement_row = rows.find { |r| r["id"] == orders.id }
    expect(Array(procurement_row["also_in"]).map { |a| a["id"] }).to include(sales_quotes.id)
  end

  it "takes only approved conclusions, with leadership's view as a material difference to validate" do
    context = leadership_context(engagement: engagement)
    concern = strategic_finding(context, statement: "Finance closes the month late")
    synthesise!
    run = SynthesisRun.latest_finished(engagement)
    validation = ManagementValidation.current.find_by!(strategic_finding: concern)
    opportunity = ConsultancyOpportunity.current.first

    expect(Synthesis::ForReport.call(company)).to eq({})

    decide("APPROVE_OPERATING_PICTURE", run)
    decide("RESOLVE_VALIDATION", validation, relationship: "POINTS_ELSEWHERE", material: true)
    decide("RECLASSIFY_OPPORTUNITY", opportunity, level: "DEPARTMENT")
    synthesis = Synthesis::ForReport.call(company)

    expect(synthesis["operating_picture"]["how_the_business_runs"]).to be_present
    expect(synthesis["opportunities"].map { |o| o["level"] }).to eq(["DEPARTMENT"])
    expect(synthesis["management_views"].sole).to include("management_reports" => "Finance closes the month late",
                                                           "fact_status" => "CONTRADICTED")
    expect(synthesis.to_json).not_to include("evidence", "sf_", "wi_")
  end

  it "renders the approved picture and the shared work inside the findings" do
    context = leadership_context(engagement: engagement)
    strategic_finding(context, statement: "Purchase orders take too long")
    synthesise!
    decide("APPROVE_CLUSTER", SynthesisCluster.current.sole)
    decide("APPROVE_OPERATING_PICTURE", SynthesisRun.latest_finished(engagement))
    decide("RECLASSIFY_OPPORTUNITY", ConsultancyOpportunity.current.first, level: "PROCESS")
    validation = ManagementValidation.current.first
    decide("RESOLVE_VALIDATION", validation, relationship: "POINTS_ELSEWHERE", material: true,
                                             resolution: "Approvals, not ordering, hold orders up.")

    snapshot = Reports::SnapshotBuilder.call(company: company, delta: {})
    html = Reports::HtmlBuilder.call(snapshot: snapshot)

    expect(html).to include("How the business runs today", "What connects the findings", "Counted once, with",
                            "Management reports: Purchase orders take too long",
                            "Approvals, not ordering, hold orders up.")
    expect(snapshot["patterns"]).to eq([])
  end
end
