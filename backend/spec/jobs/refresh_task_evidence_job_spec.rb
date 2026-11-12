# frozen_string_literal: true

require "rails_helper"

RSpec.describe RefreshTaskEvidenceJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:trigger) { "Suppliers submit signed invoice documents" }
  let(:output) { "Validated invoices sent to ledger" }

  def conversation_for(company)
    create(:conversation, employee: create(:employee, company: company), langgraph_thread_id: SecureRandom.uuid)
  end

  def blackboard_for(message, revision:, trigger:, output:)
    evidence = { "message_id" => message.id, "turn" => 2, "quote" => message.body }
    facts = { "steps_decisions" => "Match invoices against supplier orders",
              "trigger_inputs" => trigger, "output_recipient" => output }.compact.transform_values do |value|
      { "status" => "known", "value" => value, "evidence" => evidence }
    end
    {
      "dossier" => {
        "workflow" => { "revision" => revision, "tasks" => [
          { "id" => "task-1", "name" => "Invoice review", "evidence" => evidence, "facts" => facts }
        ] }
      }
    }
  end

  def write_evidence(conversation, revision: 1, trigger: self.trigger, output: self.output)
    message = create(:message, conversation: conversation, track: "discovery")
    conversation.update!(state_snapshot: { "blackboard" => blackboard_for(message, revision: revision,
                                                                          trigger: trigger, output: output) })
    message
  end

  def tick
    described_class.perform_now
  end

  it "projects a Discovery turn, replaces an uncertain grouping with a supported match, and preserves history" do
    left = conversation_for(company)
    right = conversation_for(company)
    left_answer = write_evidence(left)
    old_answer = write_evidence(right, trigger: "Treasury flags unmatched supplier deposits", output: nil)
    tick

    first_run = TaskIntelligenceRun.where(company: company).sole
    first_proposals = first_run.candidates.order(:id).to_a
    first_members = first_proposals.map { |row| row.process_cluster_revision.memberships.pluck(:task_source_id) }
    expect(first_proposals.map(&:disposition)).to contain_exactly("shortlisted", "needs_overlap_review")
    expect(first_proposals.first.process_cluster_revision.relationships.pluck("kind")).to include("uncertain")

    create(:discovery_playbook, department: "default")
    corrected_answer = create(:message, conversation: right, track: "discovery")
    agent = instance_double(Langgraph::Client)
    allow(Langgraph::Client).to receive(:new).and_return(agent)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    allow(OpenaiCircuitBreaker).to receive(:reset!)
    allow(agent).to receive(:run_turn!).and_return(
      "assistant_message" => "Thanks. Who handles the next step?", "question_count" => 4, "completed" => false,
      "blackboard" => blackboard_for(corrected_answer, revision: 2, trigger: trigger, output: output)
    )
    Discovery::ProcessTurnService.call(conversation: right.reload, employee: right.employee,
                                       user_message: corrected_answer.body, inbound_message: corrected_answer)
    expect(TaskEvidenceRefresh.find_by!(conversation: right)).to be_projection_pending
    expect(right.task_sources.count).to eq(1)
    tick

    newer = TaskIntelligenceRun.where(company: company).order(:version).last
    expect(newer.version).to eq(2)
    revision = newer.candidates.sole.process_cluster_revision
    expect(revision.relationships.pluck("kind")).to eq(["same_work"])
    expect(revision.memberships.map(&:task_source).map(&:version)).to contain_exactly(1, 2)
    expect(revision.memberships.map(&:task_source).flat_map(&:evidence_references).pluck("message_id").uniq)
      .to contain_exactly(left_answer.id, corrected_answer.id)
    expect(right.task_sources.find_by!(version: 1).evidence_references.pluck("message_id").uniq).to eq([old_answer.id])
    expect(first_run.candidates.order(:id).ids).to eq(first_proposals.map(&:id))
    expect(first_run.candidates.order(:id).map { |row| row.process_cluster_revision.memberships.pluck(:task_source_id) })
      .to eq(first_members)
    expect(ProcessCluster.where(company: company, active: false).sole.current_revision.status).to eq("retired")
  end

  it "coalesces multiple turns and conversations, and skips idle or metadata-only ticks" do
    left = conversation_for(company)
    right = conversation_for(company)
    allow(ProcessClusters::Rebuild).to receive(:call).and_call_original
    allow(TaskIntelligence::Generate).to receive(:call).and_call_original

    expect do
      write_evidence(left)
      write_evidence(left, revision: 2)
      write_evidence(right)
    end.not_to have_enqueued_job(described_class)
    expect(TaskEvidenceRefresh.for_company(company.id).count).to eq(2)
    expect(TaskSource.count).to eq(0)
    tick
    expect(left.task_sources.sole.discovery_revision).to eq(2)
    expect(TaskEvidenceRefresh.pending_projection).to be_empty
    expect(TaskEvidenceRefresh.pending_publication).to be_empty

    left.reload.update_blackboard!("conversation_summary" => "New summary only")
    snapshot = left.reload.state_snapshot.deep_dup
    snapshot["blackboard"]["dossier"]["workflow"]["revision"] = 3
    left.update!(state_snapshot: snapshot)
    TaskSources::SyncFromConversation.call(conversation: left)
    tick
    expect(ProcessClusters::Rebuild).to have_received(:call).once
    expect(TaskIntelligence::Generate).to have_received(:call).once
    expect(TaskIntelligenceRun.count).to eq(1)
    expect(left.task_sources.count).to eq(1)
  end

  it "does not retain projection work from an uncommitted Discovery update" do
    conversation = conversation_for(company)
    Conversation.transaction(requires_new: true) do
      write_evidence(conversation)
      expect(TaskEvidenceRefresh.pending_projection).not_to be_empty
      raise ActiveRecord::Rollback
    end

    tick
    expect(TaskEvidenceRefresh.count).to eq(0)
    expect(TaskSource.count).to eq(0)
  end

  it "publishes source changes from the existing Findings job without rewriting a custom target" do
    conversation = conversation_for(company)
    write_evidence(conversation)
    BuildFindingsJob.perform_now(conversation.id)
    expect(TaskEvidenceRefresh.find_by!(conversation: conversation).source_generation).to eq(1)
    tick
    chosen = TaskIntelligence::Generate.call(company: company, target: 7)

    write_evidence(conversation, revision: 2, output: "Validated invoices reviewed by treasury")
    tick
    latest = TaskIntelligenceRun.where(company: company).order(:version).last
    expect(latest).to have_attributes(target_size: 7, version: chosen.version + 1)
    expect(TaskEvidenceRefresh.pending_publication).to be_empty
  end

  it "retires unsupported sources without erasing them and can restore the same logical activity" do
    conversation = conversation_for(company)
    write_evidence(conversation)
    tick
    original = conversation.task_sources.sole
    first_proposal = TaskIntelligenceRun.where(company: company).sole.candidates.sole

    conversation.update!(state_snapshot: { "blackboard" => { "dossier" => { "workflow" => { "tasks" => [] } } } })
    tick
    expect(conversation.task_sources.order(:version).last).to have_attributes(retired: true, version: 2)
    expect(ProcessCluster.where(company: company, active: true)).to be_empty
    expect(TaskIntelligenceRun.where(company: company).order(:version).last.candidates).to be_empty
    expect(first_proposal.reload.process_cluster_revision.memberships.sole.task_source_id).to eq(original.id)

    write_evidence(conversation, revision: 3)
    tick
    restored = conversation.task_sources.order(:version).last
    expect(restored).to have_attributes(retired: false, version: 3)
    expect(ProcessCluster.where(company: company, active: true).sole.id)
      .to eq(first_proposal.process_cluster_revision.process_cluster_id)
  end

  it "rolls back a failed publication, exposes the failure, and retries without losing earlier results" do
    conversation = conversation_for(company)
    write_evidence(conversation)
    tick
    previous_run = TaskIntelligenceRun.where(company: company).sole
    cluster = ProcessCluster.where(company: company).sole
    first_revision_id = cluster.current_revision.id
    write_evidence(conversation, revision: 2, output: "Validated invoices sent to treasury")
    calls = 0
    allow(TaskIntelligence::Generate).to receive(:call).and_wrap_original do |original, **args|
      calls += 1
      raise "test publication failure" if calls == 1

      original.call(**args)
    end

    tick
    request = TaskEvidenceRefresh.find_by!(conversation: conversation)
    expect(request).to have_attributes(failure_stage: "publication", last_error_class: "RuntimeError", attempts: 1)
    expect(request.source_generation).to be > request.published_generation
    expect(cluster.reload.current_revision.id).to eq(first_revision_id)
    expect(TaskIntelligenceRun.where(company: company).sole.id).to eq(previous_run.id)
    tick
    expect(calls).to eq(1)

    travel 61.seconds do
      tick
      expect(calls).to eq(2)
      expect(request.reload).to have_attributes(attempts: 0, retry_at: nil, failure_stage: nil)
      expect(request.published_generation).to eq(request.source_generation)
      expect(cluster.reload.current_revision.number).to eq(2)
      expect(previous_run.candidates.sole.process_cluster_revision_id).to eq(first_revision_id)
    end
  end

  it "retries a failed projection without publishing an unprojected company snapshot" do
    conversation = conversation_for(company)
    write_evidence(conversation)
    calls = 0
    allow(TaskSources::SyncFromConversation).to receive(:call).and_wrap_original do |original, **args|
      calls += 1
      raise "test projection failure" if calls == 1

      original.call(**args)
    end
    tick
    expect(TaskEvidenceRefresh.find_by!(conversation: conversation)).to have_attributes(
      projection_pending: true, attempts: 1, failure_stage: "projection"
    )
    expect(TaskIntelligenceRun.where(company: company)).to be_empty

    travel 61.seconds do
      tick
      expect(TaskIntelligenceRun.where(company: company).sole.candidates.count).to eq(1)
    end
  end

  it "does not acknowledge newer work that arrived during publication" do
    conversation = conversation_for(company)
    write_evidence(conversation)
    allow(TaskIntelligence::Generate).to receive(:call).and_wrap_original do |original, **args|
      original.call(**args).tap { TaskEvidenceRefresh.record_source_change(conversation.id) }
    end
    tick
    request = TaskEvidenceRefresh.find_by!(conversation: conversation)
    expect(request).to have_attributes(source_generation: 2, published_generation: 0)

    allow(TaskIntelligence::Generate).to receive(:call).and_call_original
    tick
    expect(request.reload.published_generation).to eq(2)
    expect(TaskIntelligenceRun.where(company: company).count).to eq(1)
  end
end
