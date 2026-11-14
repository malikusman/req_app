# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessClusters::Rebuild do
  let(:company) { create(:company) }
  let(:trigger) { "Supplier sends a signed invoice batch" }
  let(:steps) { "Match supplier invoices against purchase orders" }
  let(:output) { "Validated invoice batch with approval stamps" }

  def activity(name: "Invoice processing", trigger: self.trigger, steps: self.steps, output: self.output,
               effort: nil, bottleneck: nil, tools: nil, previous: nil, company: self.company, employee: nil)
    conversation = previous&.conversation || create(:conversation, employee: employee || create(:employee, company: company))
    message = create(:message, conversation: conversation, track: "discovery")
    anchor = { "message_id" => message.id, "turn" => 2 }
    facts = {
      "trigger_inputs" => trigger, "steps_decisions" => steps, "output_recipient" => output,
      "active_effort" => effort, "bottlenecks" => bottleneck, "tools" => tools
    }.compact.transform_values do |value|
      fact = { "status" => "known", "evidence" => anchor }
      value.is_a?(Hash) ? fact.merge("effort" => value) : fact.merge("value" => value)
    end
    conversation.task_sources.create!(
      company: company, employee: conversation.employee, local_task_id: "task-1", source_kind: "workflow_ledger",
      name: name, version: (previous&.version || 0) + 1, discovery_revision: (previous&.discovery_revision || 0) + 1,
      source_snapshot: { "facts" => facts }, evidence_references: [anchor]
    )
  end

  def reported_effort(type: "active", duration: 15, unit: "minutes")
    {
      "effort_type" => type,
      "frequency" => { "min" => 10, "max" => 12, "unit" => "per_week", "as_said" => "Ten to twelve a week" },
      "duration" => { "min" => duration, "max" => duration, "unit" => unit, "as_said" => "My original estimate" }
    }
  end

  def rebuild
    described_class.call(company: company)
  end

  it "groups evidence-backed accounts even with different titles and never adds overlapping effort" do
    left = activity(name: "Invoice checks", effort: reported_effort)
    right = activity(name: "Purchase order matching", effort: reported_effort(duration: 20))
    activity(company: create(:company))

    revision = rebuild.sole.current_revision
    expect(revision.memberships.pluck(:task_source_id)).to contain_exactly(left.id, right.id)
    expect(revision).to have_attributes(confidence: "high")
    expect(revision.relationships).to contain_exactly(hash_including("kind" => "same_work", "classification" => "SHARED_IDENTICAL"))
    expect(revision.effort_summary).to include("status" => "potential_overlap", "annual_hours_max" => nil,
                                              "quantified_source_count" => 2)
    expect(revision.memberships.find_by!(task_source: left).effort_observations.sole).to include(
      "annual_hours_min" => 120, "annual_hours_max" => 145,
      "duration" => hash_including("unit" => "minutes", "as_said" => "My original estimate")
    )
  end

  it "groups supported process variants without adding their effort" do
    left = activity(steps: "Match supplier invoices against purchase orders and record exceptions", effort: reported_effort)
    right = activity(steps: "Match supplier invoices against purchase orders and escalate exceptions", effort: reported_effort)

    revision = rebuild.sole.current_revision
    expect(revision.relationships).to contain_exactly(hash_including("classification" => "SHARED_VARIANT"))
    expect(revision.memberships.pluck(:task_source_id)).to contain_exactly(left.id, right.id)
    expect(revision.effort_summary).to include("status" => "potential_overlap", "annual_hours_max" => nil)
  end

  it "recognizes different reported tools within the same recorded scope" do
    activity(tools: "SAP accounts payable")
    activity(tools: "Local spreadsheet")

    expect(rebuild.sole.current_revision.relationships).to contain_exactly(
      hash_including("kind" => "shared_variant", "classification" => "SHARED_VARIANT")
    )
  end

  it "keeps matching titles separate and flags similar steps with weak boundaries" do
    left = activity
    related = activity(trigger: "Treasury flags the month's unmatched deposits", output: nil)
    unrelated = activity(trigger: nil, output: nil, steps: "Upload payroll tax receipts into archive")

    revisions = rebuild.map(&:current_revision)
    expect(revisions.map { |revision| revision.memberships.pluck(:task_source_id) })
      .to contain_exactly([left.id], [related.id], [unrelated.id])
    expect(revisions.first.relationships).to contain_exactly(hash_including("kind" => "uncertain", "classification" => "UNRESOLVED"))
    expect(revisions.last.relationships).to be_empty
  end

  it "deduplicates a material request and versions the same request as the evidence changes" do
    left = activity(effort: reported_effort)
    right = activity(trigger: nil, output: nil)
    clusters = rebuild
    request = ClarificationRequest.sole
    original = request.snapshot
    expect(request).to have_attributes(status: "open", version: 1)
    expect(request.details.fetch("impacts")).to contain_exactly("effort_estimation", "participant_sampling")
    expect(request.details.fetch("affected_sources")).to contain_exactly(
      hash_including("task_source_id" => left.id, "evidence_references" => include(hash_including("message_id"))),
      hash_including("task_source_id" => right.id)
    )
    expect(clusters.first.current_revision.relationships.sole["clarification_request"]).to eq(original)

    expect { rebuild }.not_to change(ProcessClusterRevision, :count)
    expect(request.reload.version).to eq(1)
    updated = activity(previous: right, output: nil)
    rebuild
    expect(request.reload).to have_attributes(status: "open", version: 2, right_source_id: updated.id)
    expect(request.history).to eq([original])
    expect(request.details.fetch("missing_evidence")).not_to include("Comparable trigger and inputs for both activities.")
    expect(ClarificationRequest.count).to eq(1)
  end

  it "records uncertainty without a request when neither effort nor participant sampling is affected" do
    left = activity
    activity(employee: left.employee, trigger: nil, output: nil)

    expect(rebuild.first.current_revision.relationships.sole["classification"]).to eq("UNRESOLVED")
    expect(ClarificationRequest.count).to eq(0)
  end

  it "closes a request without claiming resolution when the comparison loses its evidence" do
    activity
    right = activity(trigger: nil, output: nil)
    rebuild
    request = ClarificationRequest.sole

    activity(previous: right, trigger: nil, output: nil, steps: "Archive payroll remittance acknowledgements")
    rebuild

    expect(request.reload).to have_attributes(status: "closed", version: 2)
    expect(request.details.fetch("resolution")).not_to have_key("classification")
    expect(request.history.sole.fetch("status")).to eq("open")
  end

  it "flags related but distinct activities when only a boundary matches" do
    activity
    activity(steps: "File exception escalation ticket with compliance", output: "Case number recorded against escalation")

    revisions = rebuild.map(&:current_revision)
    expect(revisions.size).to eq(2)
    expect(revisions.first.relationships).to contain_exactly(hash_including("kind" => "related_distinct", "classification" => "DISTINCT"))
  end

  it "sums independent active effort for evidenced stages while preserving waiting separately" do
    left = activity(effort: reported_effort, bottleneck: reported_effort(type: "waiting", duration: 2, unit: "days"))
    right = activity(trigger: output, steps: "Post approved batch to finance journal",
                     output: "Posted finance journal lines", effort: reported_effort(duration: 10))

    revision = rebuild.sole.current_revision
    expect(revision.relationships).to contain_exactly(
      hash_including("kind" => "different_stages", "classification" => "DISTINCT", "source_ids" => [left.id, right.id])
    )
    expect(revision.effort_summary).to include("status" => "separate_stages", "annual_hours_min" => 200,
                                              "annual_hours_max" => 245, "waiting_observation_count" => 1)
    waiting = revision.memberships.find_by!(task_source: left).effort_observations.find { |item| item["effort_type"] == "waiting" }
    expect(waiting["duration"]).to include("unit" => "days", "min" => 2)
    expect(waiting).not_to have_key("annual_hours_max")
  end

  it "leaves the combined estimate unknown when a stage has mixed effort" do
    activity(effort: reported_effort)
    activity(trigger: output, steps: "Post approved batch to finance journal",
             output: "Posted finance journal lines", effort: reported_effort(type: "mixed"))

    expect(rebuild.sole.current_revision.effort_summary).to include(
      "status" => "separate_stages_incomplete", "annual_hours_min" => nil, "quantified_source_count" => 1
    )
  end

  it "retains legacy bottleneck units without treating them as process effort" do
    conversation = create(:conversation, employee: create(:employee, company: company), status: "completed")
    conversation.update!(state_snapshot: { blackboard: { dossier: { slots: {
      "how_it_works::Invoices" => { value: steps, confidence: 0.9, turn: 2 },
      "friction_cost::Invoices" => { value: "Manual checks", confidence: 0.9, turn: 3, effort: reported_effort }
    } } } })
    source = TaskSources::SyncFromConversation.call(conversation: conversation).sole

    revision = rebuild.sole.current_revision
    expect(revision.effort_summary).to include("status" => "unknown", "annual_hours_max" => nil)
    expect(revision.memberships.find_by!(task_source: source).effort_observations.sole).to include(
      "scope" => "bottleneck", "frequency" => hash_including("unit" => "per_week")
    )
  end

  it "does not chain stage matches through an unsupported third pair" do
    activity
    activity(trigger: output, steps: "Post approved batch to finance journal", output: "Posted journal export ready for treasury")
    activity(trigger: "Posted journal export ready for treasury", steps: "Import bank settlement into treasury system", output: nil)

    expect(rebuild.map { |cluster| cluster.current_revision.memberships.count }).to contain_exactly(2, 1)
  end

  it "does not duplicate clusters, revisions or memberships on a repeated build" do
    2.times { activity }
    cluster = rebuild.sole
    counts = [ProcessCluster.count, ProcessClusterRevision.count, ProcessClusterMembership.count]

    expect(rebuild.sole.id).to eq(cluster.id)
    expect([ProcessCluster.count, ProcessClusterRevision.count, ProcessClusterMembership.count]).to eq(counts)
  end

  it "pins source revisions, retires an absorbed cluster and retains its history" do
    left = activity
    right = activity(steps: "File payroll tax receipts in archive", output: nil)
    first, second = rebuild
    updated = activity(previous: right)

    expect(rebuild.sole.id).to eq(first.id)
    expect(first.reload.revisions.find_by!(number: 1).memberships.pluck(:task_source_id)).to eq([left.id])
    expect(first.current_revision.memberships.pluck(:task_source_id)).to contain_exactly(left.id, updated.id)
    expect(second.reload).to have_attributes(active: false)
    expect(second.current_revision).to have_attributes(number: 2, status: "retired")
    expect(second.revisions.find_by!(number: 1).memberships.pluck(:task_source_id)).to eq([right.id])
  end
end
