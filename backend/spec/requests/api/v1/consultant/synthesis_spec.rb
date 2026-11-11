# frozen_string_literal: true

require "rails_helper"

# Doc 10 §17 and Doc 05 §9: the consultant sees what synthesis grouped and
# concluded without reading transcripts, and every decision is a new version
# with a reason, on the current version only.
RSpec.describe "Consultant synthesis review", type: :request do
  include ActiveJob::TestHelper

  let(:consultant) { create(:consultant_user) }
  let(:headers) { auth_headers_for(consultant) }
  let(:company) { create(:company, :onboarded) }
  let!(:engagement) { create(:engagement, company: company, lead_consultant: consultant) }
  let(:path) { "/api/v1/consultant/companies/#{company.id}/synthesis" }
  let(:sales) { create(:employee, company: company, display_name: "Omar Siddiqui", role_title: "Sales Coordinator", department: "Sales") }

  before do
    create(:consultant_assignment, consultant_user: consultant, company: company, status: "active")
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
  end

  def quote_finding(hours: [100, 150], employee: nil)
    synthesis_finding(company: company, role: "Sales Coordinator", employee: employee, title: "Preparing quotes",
                      what_happens_now: "Check stock and the price list, fill the quotation template, email the customer",
                      hours: hours)
  end

  def synthesise!
    run = SynthesisRun.create!(company: company, engagement: engagement, trigger: "MANUAL", requested_at: Time.current,
                               version: (SynthesisRun.where(engagement: engagement).maximum(:version) || 0) + 1)
    Synthesis::Run.call(run, client: Synthesis::ScriptedClient.new)
  end

  def decide(action, subject_id: nil, rationale: "Checked against the interviews", **details)
    post "#{path}/decisions", params: { decision_action: action, subject_id: subject_id, rationale: rationale,
                                        details: details }, headers: headers, as: :json
  end

  let!(:first) { quote_finding(hours: [100, 150], employee: sales) }
  let!(:second) { quote_finding(hours: [80, 120]) }
  let!(:third) { quote_finding(hours: [60, 90]) }

  before { synthesise! }

  let(:cluster) { ProcessCluster.current.sole }

  it "shows clusters by role with raw and de-duplicated effort, and no names" do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body

    shown = body["clusters"].sole
    expect(shown["members"].map { |m| m["role"] }.uniq).to eq(["Sales Coordinator"])
    expect(shown["effort"]).to include("raw_min" => 240.0, "dedup_max" => 360.0)
    expect(shown["sampling"]["recommended"].size).to eq(1)
    expect(body["status"]).to eq("needs_review")
    expect(response.body).not_to include("Omar")
  end

  it "approves a cluster as a new version, with the reason logged" do
    decide("APPROVE_CLUSTER", subject_id: cluster.id)
    expect(response).to have_http_status(:ok)

    approved = ProcessCluster.current.sole
    expect(approved).to have_attributes(status: "APPROVED", version: 2, parent_version_id: cluster.id,
                                        fact_status: "CONSULTANT_CONFIRMED")
    expect(approved.effort_normalization).to be_present
    expect(SynthesisDecision.sole).to have_attributes(action: "APPROVE_CLUSTER", before_version_id: cluster.id,
                                                      after_version_id: approved.id, actor: consultant)
  end

  it "refuses a decision without a reason, or on a version someone already replaced" do
    decide("APPROVE_CLUSTER", subject_id: cluster.id, rationale: " ")
    expect(response).to have_http_status(:unprocessable_entity)

    decide("APPROVE_CLUSTER", subject_id: cluster.id)
    decide("APPROVE_CLUSTER", subject_id: cluster.id)
    expect(response).to have_http_status(:conflict)
  end

  it "splits a cluster, keeps the parts apart on the next run, and re-runs synthesis" do
    decide("SPLIT_CLUSTER", subject_id: cluster.id, groups: [[first.id, second.id], [third.id]])
    expect(response).to have_http_status(:ok)

    split = ProcessCluster.current.where.not(status: "REJECTED").sole
    expect(split.finding_ids).to contain_exactly(first.id, second.id)
    expect(split.effort_normalization).to have_attributes(raw_min: 180, raw_max: 270)
    expect(enqueued_jobs.map { |j| j["job_class"] }).to include("SynthesisRunJob")

    synthesise!
    expect(ProcessCluster.current.flat_map(&:finding_ids)).not_to include(third.id)
  end

  it "refuses a split that loses or repeats an item" do
    decide("SPLIT_CLUSTER", subject_id: cluster.id, groups: [[first.id], [first.id, second.id]])
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "overrides effort with a reason, keeping the raw figures" do
    decide("OVERRIDE_EFFORT", subject_id: cluster.id, min: 150, max: 200)
    normalization = ProcessCluster.current.sole.effort_normalization

    expect([normalization.hours_min, normalization.hours_max]).to eq([150, 200])
    expect(normalization.raw_min).to eq(240)
    expect(normalization.override_rationale).to eq("Checked against the interviews")

    decide("OVERRIDE_EFFORT", subject_id: ProcessCluster.current.sole.id, min: -1, max: 10)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "merges a suggested newcomer into a consultant's cluster" do
    decide("APPROVE_CLUSTER", subject_id: cluster.id)
    newcomer = quote_finding(hours: [10, 20])
    synthesise!

    get path, headers: headers
    expect(response.parsed_body.dig("run", "suggested_additions").map { |s| s["finding_id"] }).to include(newcomer.id)

    decide("MERGE_CLUSTERS", subject_id: ProcessCluster.current.sole.id, finding_ids: [newcomer.id])
    expect(ProcessCluster.current.sole.finding_ids).to include(newcomer.id)
  end

  it "resolves a leadership verdict, keeping the original conflict in the earlier version" do
    context = leadership_context(engagement: engagement)
    concern = strategic_finding(context, statement: "Finance closes the month late")
    synthesise!
    validation = ManagementValidation.current.find_by!(strategic_finding: concern)

    decide("RESOLVE_VALIDATION", subject_id: validation.id, relationship: "POINTS_ELSEWHERE", material: true,
                                 resolution: "Approvals in sales hold the close up")
    resolved = ManagementValidation.current.find_by!(strategic_finding: concern)
    expect(resolved).to have_attributes(status: "RESOLVED", relationship: "POINTS_ELSEWHERE", material: true)
    expect(validation.reload).to have_attributes(status: "SUPERSEDED", relationship: validation.relationship)
  end

  it "approves, reclassifies and adds opportunities, keeping management importance apart" do
    opportunity = ConsultancyOpportunity.current.sole
    decide("RECLASSIFY_OPPORTUNITY", subject_id: opportunity.id, level: "DEPARTMENT", recommended_next_action: "DIRECT_FINDING")
    expect(ConsultancyOpportunity.current.sole).to have_attributes(level: "DEPARTMENT", status: "APPROVED", version: 2)

    decide("ADD_OPPORTUNITY", level: "COMPANY_WIDE", category: "TRAINING", title: "Spreadsheet skills",
                              problem_statement: "Teams rebuild the same sheets.")
    added = ConsultancyOpportunity.current.find_by!(origin: "CONSULTANT")
    expect(added).to have_attributes(status: "APPROVED", recommended_next_action: "DIRECT_FINDING", management_importance: nil)
  end

  it "edits and approves the operating picture" do
    run = SynthesisRun.latest_finished(engagement)
    decide("EDIT_OPERATING_PICTURE", subject_id: run.id,
                                     operating_picture: { how_the_business_runs: "Sales quotes; the warehouse ships." })
    expect(run.reload).to have_attributes(operating_picture_status: "APPROVED")
    expect(run.display_operating_picture["how_the_business_runs"]).to eq("Sales quotes; the warehouse ships.")
    expect(run.operating_picture).to be_present
  end

  it "settles a pair the model couldn't" do
    stub_const("ENV", ENV.to_h.merge("AI_SYNTHESIS" => "false"))
    quote_finding(hours: [5, 10])
    synthesise!
    pair = ProcessRelationship.current.find_by!(origin: "FALLBACK")

    decide("CLASSIFY_PAIR", subject_id: pair.id, relationship_type: "SAME_PROCESS", same_execution: "NO", together: true)
    expect(ProcessRelationship.current.find_by!(from_finding_id: pair.from_finding_id, to_finding_id: pair.to_finding_id))
      .to have_attributes(origin: "CONSULTANT", recommendation: "PROVISIONAL_CLUSTER")
  end

  it "queues a run straight away when asked" do
    post "#{path}/run", headers: headers
    expect(response).to have_http_status(:accepted)
    expect(SynthesisRun.where(engagement: engagement, status: "QUEUED").count).to eq(1)
  end

  it "shows nothing for a company the consultant isn't assigned to" do
    other = create(:company, :onboarded)
    create(:engagement, company: other)
    get "/api/v1/consultant/companies/#{other.id}/synthesis", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "refuses a decision on another engagement's records" do
    other = create(:engagement, company: create(:company, :onboarded))
    foreign = ProcessCluster.create!(company: other.company, engagement: other, cluster_key: "cl-x", name: "x",
                                     cluster_type: "SHARED_IDENTICAL", schema_version: "PC.v1")
    decide("APPROVE_CLUSTER", subject_id: foreign.id)
    expect(response).to have_http_status(:not_found)
  end
end
