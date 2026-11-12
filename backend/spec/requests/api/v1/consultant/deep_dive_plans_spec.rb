# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant Deep Dive plans", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company, :onboarded) }
  let(:consultant) { create(:consultant_user) }
  let(:headers) { auth_headers_for(consultant) }
  let!(:assignment) { create(:consultant_assignment, company: company, consultant_user: consultant, status: "active") }
  let!(:source) { activity("Reported trigger with signed invoices") }
  let!(:other) { activity(nil) }
  let!(:run) do
    ProcessClusters::Rebuild.call(company: company)
    TaskIntelligence::Generate.call(company: company)
  end
  let(:proposal) { run.candidates.find { |candidate| candidate.process_cluster_revision.memberships.pluck(:task_source_id) == [source.id] } }
  let(:task_key) { "proposal-#{proposal.id}" }
  let(:path) { "/api/v1/consultant/companies/#{company.id}/task_intelligence_runs/#{run.id}/deep_dive_plans" }
  let(:task_path) { "#{path}/#{task_key}" }
  let(:client) { instance_double(Langgraph::Client) }

  before { allow(Langgraph::Client).to receive(:new).and_return(client) }

  def activity(trigger)
    employee = create(:employee, company: company, role_title: "Accounts clerk", consent_given_at: Time.current)
    conversation = create(:conversation, employee: employee)
    message = create(:message, conversation: conversation, track: "discovery", body: "Private raw transcript")
    reference = { message_id: message.id, turn: 2 }
    facts = { "steps_decisions" => "Match supplier invoices to purchase orders", "trigger_inputs" => trigger }.compact
    facts.transform_values! { |value| { status: "known", value: value, evidence: reference } }
    conversation.task_sources.create!(company: company, employee: employee, source_kind: "workflow_ledger",
                                      local_task_id: "invoice", name: "Invoice processing", version: 1,
                                      source_snapshot: { facts: facts }, evidence_references: [reference])
  end

  def finalize(add_manual: false)
    review = TaskSelection::Review.new(run)
    version = 0
    revision = nil
    commands = [{ action: "select", task_id: task_key }, { action: "participants", task_id: task_key, participant_ids: [source.employee_id] }]
    if add_manual
      commands << { action: "add", title: "Manual scope", source_ids: [] }
    end
    commands.each do |command|
      revision = review.apply(command.merge(expected_version: version, reason: "Consultant decision").stringify_keys, actor: consultant)
      version = revision.version
    end
    if add_manual
      key = revision.snapshot.fetch("tasks").last.fetch("id")
      version = review.apply({ "action" => "select", "task_id" => key, "expected_version" => version, "reason" => "Include manual scope" }, actor: consultant).version
    end
    review.apply({ "action" => "finalize", "expected_version" => version, "reason" => "Finalize the selection" }, actor: consultant)
  end

  def content
    {
      "objective" => "Confirm how invoices are matched", "scope" => "Invoice matching", "instructions" => "Verify the process before drawing conclusions.",
      "duration_minutes" => 35, "focus_areas" => ["Handoff"], "document_requests" => ["An anonymized invoice"],
      "sections" => [{ "title" => "Process and scope", "questions" => [
        { "text" => "Which steps are performed separately?", "source_ids" => [source.id],
          "clarification_ids" => ClarificationRequest.where(company: company, status: "open").pluck(:id) }
      ] }]
    }
  end

  it "requires a finalized selection, authentication and a selected task in the requested company" do
    get path, headers: headers
    expect(response).to have_http_status(:conflict)
    selection = finalize(add_manual: true)
    get path
    expect(response).to have_http_status(:unauthorized)
    get path, headers: auth_headers_for(create(:consultant_user))
    expect(response).to have_http_status(:not_found)
    get path, headers: headers
    expect(response.parsed_body.fetch("tasks").pluck("title")).to contain_exactly("Invoice processing", "Manual scope")
    expect(response.parsed_body["selection_version"]).to eq(selection.version)
    unselected = run.candidates.where.not(id: proposal.id).sole
    expect { post "#{path}/proposal-#{unselected.id}/generate", headers: headers }.not_to change(DeepDivePlan, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "creates one draft, pins safe evidence and includes current open clarifications" do
    selection = finalize
    request = ClarificationRequest.where(company: company).sole
    expect(client).to receive(:generate_deep_dive_plan!).once do |context:|
      expect(context).to include("selection_revision_id" => selection.id, "run_id" => run.id,
                                 "sources" => [hash_including("id" => source.id, "conversation_id" => source.conversation_id)],
                                 "participants" => [hash_including("id" => source.employee_id, "role_title" => "Accounts clerk")],
                                 "open_clarifications" => [hash_including("id" => request.id, "source_ids" => match_array([source.id, other.id]))])
      expect(context.to_json).not_to include("Private raw transcript", "display_name")
      { "generated_by" => "llm", "plan" => content }
    end

    expect do
      post "#{task_path}/generate", headers: headers
      post "#{task_path}/generate", headers: headers
    end.to have_enqueued_job(GenerateDeepDivePlanJob).once
    perform_enqueued_jobs
    expect(DeepDivePlan.count).to eq(1)
    post "#{task_path}/generate", headers: headers
    expect(response.parsed_body).to include("status" => "draft", "version" => 1, "content" => content)
    expect(response.parsed_body.dig("context", "sources", 0, "facts")).to include(
      hash_including("field" => "steps_decisions", "reference" => hash_including("message_id"))
    )
  end

  it "reports failure, retries the existing plan, and rejects synthetic or incomplete AI responses" do
    finalize
    allow(client).to receive(:generate_deep_dive_plan!).and_raise(Langgraph::UnavailableError.new("unavailable", retryable: true))
    perform_enqueued_jobs { post "#{task_path}/generate", headers: headers }
    expect(response.parsed_body).to include("status" => "failed", "content" => nil, "retry_available" => true,
                                           "generation_error" => include("unavailable"))
    allow(client).to receive(:generate_deep_dive_plan!).and_return("generated_by" => "fallback", "plan" => content)
    perform_enqueued_jobs { post "#{task_path}/generate", headers: headers }
    expect(response.parsed_body).to include("status" => "failed", "content" => nil)
    missing_gap = content.deep_dup
    missing_gap.dig("sections", 0, "questions", 0)["clarification_ids"] = []
    allow(client).to receive(:generate_deep_dive_plan!).and_return("generated_by" => "llm", "plan" => missing_gap)
    perform_enqueued_jobs { post "#{task_path}/generate", headers: headers }
    expect(response.parsed_body).to include("status" => "failed", "content" => nil)
    allow(client).to receive(:generate_deep_dive_plan!).and_return("generated_by" => "llm", "plan" => content)
    perform_enqueued_jobs { post "#{task_path}/generate", headers: headers }
    expect(response.parsed_body).to include("status" => "draft", "version" => 1)
    expect(DeepDivePlan.count).to eq(1)
    expect(DeepDivePlanRevision.count).to eq(1)
  end

  it "versions consultant edits and locks the approved snapshot with an audit reason" do
    finalize
    allow(client).to receive(:generate_deep_dive_plan!).and_return("generated_by" => "llm", "plan" => content)
    perform_enqueued_jobs { post "#{task_path}/generate", headers: headers }
    edited = content.merge("scope" => "Invoice matching and exceptions")
    patch task_path, headers: headers, as: :json, params: { expected_version: 1, reason: "Include exceptions", content: edited }
    expect(response.parsed_body).to include("version" => 2, "content" => edited)
    post "#{task_path}/approve", headers: headers, as: :json, params: { expected_version: 1, reason: "Stale approval" }
    expect(response).to have_http_status(:conflict)
    post "#{task_path}/approve", headers: headers, as: :json, params: { expected_version: 2, reason: "Ready for review" }
    expect(response.parsed_body).to include("status" => "approved", "approved_version" => 3, "content" => edited)
    expect(DeepDivePlan.sole.approved_revision).to have_attributes(content: edited, reason: "Ready for review")
    patch task_path, headers: headers, as: :json, params: { expected_version: 3, reason: "Overwrite", content: content }
    expect(response).to have_http_status(:conflict)
    post "#{task_path}/generate", headers: headers
    expect(response.parsed_body).to include("approved_version" => 3, "content" => edited)
    get task_path, params: { version: 1 }, headers: headers
    expect(response.parsed_body).to include("version" => 1, "approved_version" => 3, "content" => content)
    expect(response.parsed_body.fetch("history").pluck("action")).to eq(%w[approved edited generated])
  end
end
