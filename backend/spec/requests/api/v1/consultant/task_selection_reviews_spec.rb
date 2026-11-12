# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant task selection", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:consultant) { create(:consultant_user) }
  let(:headers) { auth_headers_for(consultant) }
  let!(:assignment) { create(:consultant_assignment, company: company, consultant_user: consultant, status: "active") }
  let!(:left) { activity }
  let!(:right) { activity(boundaries: false) }
  let!(:run) { generate }
  let(:proposals) { run.candidates.order(:id).to_a }
  let(:first) { "proposal-#{proposals.first.id}" }
  let(:second) { "proposal-#{proposals.last.id}" }

  def activity(boundaries: true, company: self.company, prior: nil)
    conversation = prior&.conversation || create(:conversation, employee: create(:employee, company: company))
    message = create(:message, conversation: conversation, track: "discovery", body: "Private invoice transcript")
    anchor = { "message_id" => message.id, "turn" => 2 }
    facts = { "steps_decisions" => "Match supplier invoices against purchase orders" }
    if boundaries
      facts.merge!("trigger_inputs" => "Supplier sends a signed invoice batch",
                   "output_recipient" => "Validated invoice batch with approval stamps")
    end
    facts.transform_values! { |value| { "status" => "known", "evidence" => anchor, "value" => value } }
    facts["active_effort"] = {
      "status" => "known", "evidence" => anchor,
      "effort" => { "effort_type" => "active",
                    "frequency" => { "min" => 10, "max" => 12, "unit" => "per_week", "as_said" => "Private estimate" },
                    "duration" => { "min" => 15, "max" => 15, "unit" => "minutes" } }
    }
    conversation.task_sources.create!(
      company: company, employee: conversation.employee, local_task_id: "task-1", source_kind: "workflow_ledger",
      name: "Invoice processing", version: (prior&.version || 0) + 1,
      source_snapshot: { "facts" => facts }, evidence_references: [anchor]
    )
  end

  def generate(company = self.company)
    ProcessClusters::Rebuild.call(company: company)
    TaskIntelligence::Generate.call(company: company, target: 1)
  end

  def path(run = self.run, company_id: company.id)
    "/api/v1/consultant/companies/#{company_id}/task_intelligence_runs/#{run.id}/selection_review"
  end

  def command(action, version:, status: :ok, **args)
    post "#{path}/commands", headers: headers, as: :json,
         params: { action: action, expected_version: version, reason: "Consultant reason #{action}" }.merge(args)
    expect(response).to have_http_status(status), response.body
    response.parsed_body
  end

  def task(body, id)
    body.dig("snapshot", "tasks").find { |item| item["id"] == id }
  end

  it "displays every original proposal, safe effort evidence and the pinned clarification" do
    expect { get path, headers: headers }.not_to change(TaskSelectionReview, :count)
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include("version" => 0, "status" => "draft")
    expect(body["proposals"].pluck("id")).to match_array(proposals.map(&:id))
    expect(body["relationships"].sole).to include(
      "classification" => "UNRESOLVED",
      "clarification_request" => hash_including("id" => ClarificationRequest.sole.id, "version" => 1, "status" => "open",
                                               "missing_evidence" => be_present, "why_it_matters" => be_present)
    )
    expect(body["sources"].first["effort_observations"].sole).to include("annual_hours_min" => 120)
    expect(response.body).not_to include("Private", "as_said", "phone_e164", "evidence_references")
  end

  it "records selection, deferral, rejection, notes and exact ordering with history and conflict protection" do
    original_proposals = proposals.map(&:attributes)
    command("select", version: 0, task_id: first)
    command("reject", version: 0, task_id: first, status: :conflict)
    command("reject", version: 1, task_id: second)
    command("defer", version: 2, task_id: second)
    command("annotate", version: 3, task_id: second)
    command("select", version: 4, task_id: second)
    command("reorder", version: 5, task_ids: [second], status: :unprocessable_entity)
    body = command("reorder", version: 5, task_ids: [second, first])
    expect(body.dig("snapshot", "selected_order")).to eq([second, first])
    expect(task(body, second)).to include("notes" => ["Consultant reason annotate"])
    expect(task(body, first)["effective_effort"]).to include("status" => "withheld_possible_overlap")
    expect(body["history"].pluck("version")).to eq([6, 5, 4, 3, 2, 1])
    get path, headers: headers, params: { version: 3 }
    expect(task(response.parsed_body, second)).to include("status" => "deferred", "notes" => [])
    expect(run.candidates.order(:id).map(&:attributes)).to eq(original_proposals)
  end

  it "adds, merges and splits without dropping lineage and flags reused source evidence" do
    original = command("add", version: 0, title: "Independent manual proposal", source_ids: [])
    manual = original.dig("snapshot", "tasks").last
    expect(manual).to include("proposal_ids" => [], "gaps" => include("No linked Discovery evidence."))
    merged = command("merge", version: 1, task_ids: [first, second], title: "Combined review")
    combined = merged.dig("snapshot", "tasks").last
    expect(combined).to include("origin_task_ids" => [first, second], "source_ids" => match_array([left.id, right.id]))
    expect(task(merged, first)["status"]).to eq("merged")
    command("split", version: 2, task_id: combined["id"], children: [
      { title: "First part", source_ids: [left.id] }, { title: "Second part", source_ids: [] }
    ], status: :unprocessable_entity)
    split = command("split", version: 2, task_id: combined["id"], children: [
      { title: "First part", source_ids: [left.id] }, { title: "Second part", source_ids: [left.id, right.id] }
    ])
    part_a, part_b = split.dig("snapshot", "tasks").last(2)
    expect(part_b).to include("origin_task_ids" => [combined["id"]], "proposal_ids" => match_array(proposals.map(&:id)))
    command("select", version: 3, task_id: part_a["id"])
    selected = command("select", version: 4, task_id: part_b["id"])
    expect(task(selected, part_a["id"])["effective_effort"]).to eq("status" => "withheld_shared_evidence")
  end

  it "recalculates conditional workload from a judgment and preserves reported uncertainty and waiting time" do
    merged = command("merge", version: 0, task_ids: [first, second], title: "Combined review")
    combined = merged.dig("snapshot", "tasks").last
    expect(combined["effective_effort"]).to eq("status" => "withheld_possible_overlap")
    body = command("relationship", version: 1, source_ids: [left.id, right.id], classification: "DISTINCT")
    expect(task(body, combined["id"])["effective_effort"]).to include(
      "status" => "conditional_consultant_assumption", "annual_hours_min" => 240
    )
    expect(body["relationships"].sole).to include("classification" => "UNRESOLVED")
    expect(ClarificationRequest.sole.status).to eq("open")
    measures = { frequency: { min: 2, max: 3, unit: "per_week" }, duration: { min: 15, max: 20, unit: "minutes" } }
    waiting = command("effort", version: 2, task_id: combined["id"], source_id: left.id, effort_type: "waiting", **measures)
    expect(task(waiting, combined["id"])["effective_effort"]).to eq("status" => "unknown_active_effort")
    active = command("effort", version: 3, task_id: combined["id"], source_id: left.id, effort_type: "active", **measures)
    expect(task(active, combined["id"])["effective_effort"]).to include("annual_hours_min" => 140, "annual_hours_max" => 195)
    expect(left.reload.evidence_references).to include(hash_including("message_id"))
  end

  it "validates participants and records unsupported sampling and capacity before provisional finalization" do
    foreign = create(:employee)
    declined = create(:employee, company: company, participation_status: "declined")
    [foreign, declined].each do |person|
      command("participants", version: 0, task_id: first, participant_ids: [person.id], status: :unprocessable_entity)
    end
    command("finalize", version: 0, status: :unprocessable_entity)
    command("select", version: 0, task_id: first)
    command("select", version: 1, task_id: second)
    command("participants", version: 2, task_id: first, participant_ids: [left.employee_id])
    body = command("participants", version: 3, task_id: second, participant_ids: [left.employee_id])
    expect(body.dig("snapshot", "tasks").flat_map { |row| row["gaps"] }).to include(include("no linked evidence"))
    body = command("capacity", version: 4, slots: 1)
    expect(body.dig("snapshot", "sampling")).to include(
      "planned_interviews" => 2, "available_slots" => 1, "gaps" => include(include("exceed"), include("multiple tasks"))
    )
    body = command("finalize", version: 5)
    selection = body.dig("snapshot", "final_selection")
    expect(body["status"]).to eq("finalized")
    expect(selection).to include("task_intelligence_run_id" => run.id, "provisional" => true)
    expect(selection["tasks"]).to all(include("source_versions" => be_present, "cluster_revision_ids" => be_present,
                                              "clarification_requests" => include(hash_including("status" => "open"))))
    command("defer", version: 6, task_id: first, status: :conflict)

    activity(prior: right)
    new_run = generate
    get path(new_run), headers: headers
    expect(response.parsed_body).to include("version" => 0, "status" => "draft")
    get path, headers: headers
    expect(response.parsed_body.dig("snapshot", "final_selection")).to eq(selection)
  end

  it "rejects cross-tenant access, unknown sources and unauthenticated writes" do
    foreign_company = create(:company)
    foreign_source = activity(company: foreign_company)
    foreign_run = generate(foreign_company)
    get path
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/commands", as: :json, params: { action: "add" }
    expect(response).to have_http_status(:unauthorized)
    get path(foreign_run, company_id: foreign_company.id), headers: headers
    expect(response).to have_http_status(:not_found)
    post "#{path(foreign_run)}/commands", headers: headers, as: :json, params: { action: "add" }
    expect(response).to have_http_status(:not_found)
    command("add", version: 0, source_ids: [foreign_source.id], title: "Foreign source", status: :unprocessable_entity)
    expect(TaskSelectionReview.count).to eq(0)
  end
end
