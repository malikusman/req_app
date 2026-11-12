# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskSources::SyncFromConversation do
  let(:conversation) { create(:conversation, status: "completed") }
  let(:answer) { create(:message, conversation: conversation, body: "I match payments to invoices.") }

  def write_ledger(conversation, answer, revision:, name: "Payment matching", history: [])
    anchor = { "message_id" => answer.id, "turn" => 3, "quote" => answer.body }
    task = {
      "id" => "task-1", "name" => name, "evidence" => anchor,
      "facts" => {
        "steps_decisions" => { "value" => answer.body, "status" => "known", "evidence" => anchor, "history" => history }
      }
    }
    conversation.update!(state_snapshot: { blackboard: { dossier: { workflow: { revision: revision, tasks: [task] } } } })
  end

  def sync(conversation)
    described_class.call(conversation: conversation)
  end

  it "projects the task, its evidence and its matching finding" do
    write_ledger(conversation, answer, revision: 4)
    finding = Finding.create!(
      company: conversation.company, employee: conversation.employee, conversation: conversation,
      source_key: Finding.discovery_source_key(conversation_id: conversation.id, area: "Payment matching"),
      area: "Payment matching", friction: "Matching is manual"
    )

    expect(sync(conversation).sole).to have_attributes(
      company_id: conversation.company_id, employee_id: conversation.employee_id, conversation_id: conversation.id,
      finding_id: finding.id, local_task_id: "task-1", name: "Payment matching", description: answer.body,
      discovery_revision: 4, version: 1, source_kind: "workflow_ledger",
      evidence_references: [{ "message_id" => answer.id, "turn" => 3 }]
    )
  end

  it "adds a source version when a finding is linked after the first projection" do
    write_ledger(conversation, answer, revision: 4)
    source = sync(conversation).sole
    finding = Finding.create!(
      company: conversation.company, employee: conversation.employee, conversation: conversation,
      source_key: Finding.discovery_source_key(conversation_id: conversation.id, area: "Payment matching"),
      area: "Payment matching", friction: "Matching is manual"
    )

    linked = sync(conversation).sole
    expect(linked).to have_attributes(version: 2, finding_id: finding.id)
    expect(source.reload.finding_id).to be_nil
    expect { sync(conversation) }.not_to change(TaskSource, :count)
  end

  it "runs from the existing findings job and is idempotent" do
    write_ledger(conversation, answer, revision: 4)

    expect { BuildFindingsJob.perform_now(conversation.id) }.to change(TaskSource, :count).by(1)
    expect { sync(conversation) }.not_to change(TaskSource, :count)
  end

  it "keeps the same local task ID and name separate across conversations" do
    other = create(:conversation, status: "completed", employee: create(:employee, company: conversation.company))
    other_answer = create(:message, conversation: other, body: answer.body)
    write_ledger(conversation, answer, revision: 1)
    write_ledger(other, other_answer, revision: 1)

    sources = sync(conversation) + sync(other)
    expect(sources.map(&:employee_id)).to eq([conversation.employee_id, other.employee_id])
    expect(sources.map(&:conversation_id)).to eq([conversation.id, other.id])
    expect(sources.map(&:id).uniq.size).to eq(2)
  end

  it "appends corrections and retains the old version and its evidence" do
    write_ledger(conversation, answer, revision: 4)
    original = sync(conversation).sole
    old_fact = original.source_snapshot.dig("facts", "steps_decisions").except("history")
    correction = create(:message, conversation: conversation, body: "I match each bank line to a receipt.")
    write_ledger(conversation, correction, revision: 5, name: "Receipt matching", history: [old_fact])

    revised = sync(conversation).sole
    expect(revised).to have_attributes(version: 2, local_task_id: "task-1", discovery_revision: 5,
                                       name: "Receipt matching", description: correction.body)
    expect(revised.evidence_references.pluck("message_id")).to contain_exactly(answer.id, correction.id)
    expect(revised.source_snapshot.dig("facts", "steps_decisions", "history")).to eq([old_fact])
    expect(original.reload).to have_attributes(version: 1, name: "Payment matching", description: answer.body,
                                               evidence_references: [{ "message_id" => answer.id, "turn" => 3 }])
    expect { sync(conversation) }.not_to change(TaskSource, :count)
  end

  it "preserves a changed snapshot even when Discovery did not advance its revision" do
    write_ledger(conversation, answer, revision: 4)
    original = sync(conversation).sole
    correction = create(:message, conversation: conversation, body: "I match payments against receipts.")
    write_ledger(conversation, correction, revision: 4)

    expect(sync(conversation).sole).to have_attributes(version: 2, discovery_revision: 4)
    expect(original.reload.description).to eq(answer.body)
  end

  it "projects attributable legacy slots without inventing a message ID" do
    conversation.update!(state_snapshot: {
      blackboard: { role_areas: [{ name: "Unsubstantiated label" }], dossier: { slots: {
        "how_it_works::Payments" => { value: "Match each receipt", confidence: 0.8, turn: 2 },
        "friction_cost::Orphaned cost" => { value: "Two hours", confidence: 0.9, turn: 3 },
        "friction::Uncertain" => { value: "Maybe delayed", confidence: 0.2, turn: 3 },
        "how_it_works::No provenance" => { value: "Review records", confidence: 0.9 }
      } } }
    })

    expect(sync(conversation).sole).to have_attributes(
      source_kind: "legacy_slots", local_task_id: "Payments", name: "Payments", description: "Match each receipt",
      discovery_revision: nil, evidence_references: [{ "turn" => 2 }]
    )
    expect { sync(conversation) }.not_to change(TaskSource, :count)
  end

  it "rejects private and foreign messages as evidence for a task" do
    private_message = create(:message, conversation: conversation, track: "companion")
    other_message = create(:message)
    [private_message, other_message].each do |message|
      write_ledger(conversation, message, revision: 4)
      expect(sync(conversation)).to be_empty
    end
  end

  it "rejects mismatched company, employee and finding links and duplicate versions" do
    write_ledger(conversation, answer, revision: 1)
    source = sync(conversation).sole
    other = create(:conversation)
    foreign_finding = Finding.create!(company: other.company, employee: other.employee, conversation: other,
                                      source_key: "other", area: "Payments", friction: "Manual work")
    invalid = source.dup
    invalid.assign_attributes(company: other.company, employee: other.employee, finding: foreign_finding)

    expect(invalid).not_to be_valid
    expect(invalid.errors.attribute_names).to include(:conversation, :version)
    invalid.assign_attributes(company: conversation.company, employee: conversation.employee)
    expect(invalid).not_to be_valid
    expect(invalid.errors.attribute_names).to include(:finding)
  end
end
