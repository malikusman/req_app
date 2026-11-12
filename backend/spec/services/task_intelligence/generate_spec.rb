# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskIntelligence::Generate do
  let(:company) { create(:company) }

  def effort(type: "active", minutes: 15)
    {
      "effort_type" => type,
      "frequency" => { "min" => 10, "max" => 12, "unit" => "per_week" },
      "duration" => { "min" => minutes, "max" => minutes, "unit" => "minutes" }
    }
  end

  def activity(name:, steps: nil, trigger: nil, output: nil, workload: nil, bottleneck: nil,
               exceptions: nil, dependencies: nil, previous: nil)
    conversation = previous&.conversation || create(:conversation, employee: create(:employee, company: company))
    message = create(:message, conversation: conversation, track: "discovery")
    reference = { "message_id" => message.id, "turn" => 2 }
    facts = { "steps_decisions" => steps, "trigger_inputs" => trigger, "output_recipient" => output,
              "active_effort" => workload, "bottlenecks" => bottleneck,
              "exceptions" => exceptions, "dependencies" => dependencies }.compact.transform_values do |value|
      fact = { "status" => "known", "evidence" => reference.merge("quote" => "Private interview wording") }
      value.is_a?(Hash) ? fact.merge("effort" => value) : fact.merge("value" => value)
    end
    conversation.task_sources.create!(
      company: company, employee: conversation.employee, source_kind: "workflow_ledger", local_task_id: "task-1",
      version: (previous&.version || 0) + 1, name: name,
      source_snapshot: { "facts" => facts }, evidence_references: [reference]
    )
  end

  def generate(**options)
    ProcessClusters::Rebuild.call(company: company)
    described_class.call(company: company, **options)
  end

  it "ranks reported effort, frequency, risk and reviewed Findings, and disposes every current cluster" do
    company.update!(company_profile: { "business_goals" => ["Improve invoice checking"] })
    source = activity(name: "Invoice checking", steps: "Match invoices against supplier orders",
                      workload: effort(minutes: 45), bottleneck: effort,
                      exceptions: "Hold mismatched supplier invoice", dependencies: "Send disputed amount for approval")
    finding = Finding.create!(company: company, employee: source.employee, conversation: source.conversation,
                              source_key: "test-invoices", area: "Invoice checking", status: "approved")
    source.dup.update!(version: 2, finding: finding)
    activity(name: "Tax filing", steps: "Archive stamped payroll returns")
    activity(name: "Missing scope", trigger: "Supplier posts a status update")

    run = generate(target: 1)
    winner = run.candidates.find_by!(disposition: "shortlisted")
    expect(winner).to have_attributes(title: "Invoice checking", rank: 1, priority: "high", confidence: "medium")
    expect(winner.assessment.fetch("score_breakdown")).to include(
      "workload" => 3, "frequency" => 3, "reviewed_finding" => 1, "business_goal_keyword_alignment" => 1
    )
    expect(winner.assessment.fetch("findings")).to contain_exactly(hash_including("id" => finding.id))
    expect(winner.assessment.fetch("possible_released_effort")).to include("annual_hours_upper_bound" => 145)
    expect(run.candidates.pluck(:disposition)).to contain_exactly("shortlisted", "deferred_capacity", "insufficient_evidence")
    expect(run.candidates.all? { |candidate| candidate.disposition_reason.present? }).to be(true)
    expect(run.evaluation_mode).to eq("deterministic")
  end

  it "favors a different investigation focus when otherwise comparable candidates compete" do
    activity(name: "Payment entry", steps: "Copy incoming deposits into register", workload: effort(minutes: 45),
             bottleneck: effort(minutes: 10))
    activity(name: "Stock entry", steps: "File warehouse receipts against bins", workload: effort(minutes: 45),
             bottleneck: effort(minutes: 10))
    activity(name: "Claim checks", steps: "Inspect damaged parcels and photo receipts",
             exceptions: "Reject claims without receipts", dependencies: "Escalate disputed claims to insurer",
             workload: effort(minutes: 10))

    shortlist = generate(target: 2).candidates.where(disposition: "shortlisted").order(:rank)
    expect(shortlist.map { |row| row.assessment.fetch("focus") }).to eq(%w[effort risk])
    expect(shortlist.first.score).to be > shortlist.last.score
    expect(shortlist.all? { |row| row.assessment.fetch("diversity_bonus_at_selection") == 2 }).to be(true)
  end

  it "allows a target beyond five and preserves distinct activities with matching titles" do
    [
      "Archive stamped payroll returns", "Approve facility repair requests", "Inspect damaged parcels manually",
      "Reconcile supplier account balances", "Publish customer satisfaction survey", "Trace inbound bank settlements"
    ].each { |steps| activity(name: "Operations", steps: steps) }

    run = generate(target: 6)
    expect(run.candidates.where(disposition: "shortlisted").count).to eq(6)
    expect(run.candidates.all? { |row| row.assessment.fetch("potential_overlap_cluster_ids").empty? }).to be(true)
  end

  it "holds a potentially duplicate cluster for review without claiming equivalence or release" do
    steps = "Match supplier invoices against purchase orders"
    activity(name: "Invoice checks", steps: steps, trigger: "A supplier submits invoice documents",
             output: "Validated batch sent to ledger", workload: effort, bottleneck: effort(minutes: 5))
    activity(name: "Supplier review", steps: steps, trigger: "Finance finds an unmatched invoice",
             workload: effort, bottleneck: effort(minutes: 5))

    run = generate
    selected = run.candidates.find_by!(disposition: "shortlisted")
    deferred = run.candidates.find_by!(disposition: "needs_overlap_review")
    expect(run.candidates.count).to eq(2)
    expect(selected.assessment.fetch("potential_overlap_cluster_ids"))
      .to eq([deferred.process_cluster_revision.process_cluster_id])
    expect(run.candidates.map { |row| row.assessment["possible_released_effort"] }).to eq([nil, nil])
    expect(selected.assessment.fetch("observed_workload")).to include("cross_cluster_overlap_unresolved" => true)
  end

  it "keeps waiting and unquantified activity out of released effort" do
    activity(name: "Waiting for an approval", steps: "Hold disputed invoice pending approval",
             workload: effort(type: "mixed"), bottleneck: effort(type: "waiting", minutes: 90))

    row = generate.candidates.sole
    expect(row.assessment).to include("observed_workload" => nil, "possible_released_effort" => nil)
    expect(row.assessment.fetch("risks")).to include("Waiting was reported separately from active work.")
  end

  it "withholds a release bound when reported bottleneck effort exceeds total active workload" do
    activity(name: "Purchase order checks", steps: "Match signed invoices to orders",
             workload: effort(minutes: 15), bottleneck: effort(minutes: 45))

    row = generate.candidates.sole
    expect(row.assessment.fetch("observed_workload")).to include("annual_hours_max" => 145)
    expect(row.assessment["possible_released_effort"]).to be_nil
  end

  it "gives high evidence confidence to corroborated core facts without adding the witnesses' effort" do
    2.times do |index|
      activity(name: "Invoice checks #{index}", steps: "Match invoices against supplier orders",
               trigger: "Suppliers submit invoice documents", output: "Validated invoices sent to ledger",
               workload: effort, bottleneck: effort(minutes: 5))
    end

    row = generate.candidates.sole
    expect(row.confidence).to eq("high")
    expect(row.assessment).to include("observed_workload" => nil, "possible_released_effort" => nil)
  end

  it "reuses unchanged runs and pins each new proposal to the corrected cluster revision" do
    first_source = activity(name: "Invoices", steps: "Review submitted supplier invoices")
    first = generate
    first_candidate = first.candidates.sole
    expect(generate.id).to eq(first.id)
    expect(TaskCandidateProposal.count).to eq(1)

    correction = activity(name: "Invoice adjustments", steps: "Match supplier credit notes", previous: first_source)
    second = generate

    expect(second.version).to eq(2)
    expect(generate.id).to eq(second.id)
    expect(second.candidates.sole.process_cluster_revision.memberships.pluck(:task_source_id)).to eq([correction.id])
    expect(first_candidate.reload.process_cluster_revision.memberships.pluck(:task_source_id)).to eq([first_source.id])
    expect(first_candidate.title).to eq("Invoices")
  end
end
