# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant task sources", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:consultant) { create(:consultant_user) }
  let(:headers) { auth_headers_for(consultant) }
  let!(:assignment) { create(:consultant_assignment, company: company, consultant_user: consultant, status: "active") }

  def path(company_id)
    "/api/v1/consultant/companies/#{company_id}/task_sources"
  end

  def source_for(conversation)
    answer = create(:message, conversation: conversation, track: "discovery", body: "Raw employee transcript")
    private_message = create(:message, conversation: conversation, track: "companion", body: "Private aside")
    conversation.task_sources.create!(
      company: conversation.company, employee: conversation.employee, source_kind: "workflow_ledger",
      local_task_id: "task-1", version: 1, discovery_revision: 5, name: "Invoice review",
      description: "Check invoices before posting",
      source_snapshot: { evidence: { quote: answer.body }, private_note: private_message.body },
      evidence_references: [{ message_id: answer.id, turn: 1, quote: answer.body },
                            { message_id: private_message.id, turn: 2 }]
    )
  end

  it "lists assigned sources and exposes only safe evidence metadata" do
    conversation = create(:conversation, employee: create(:employee, company: company))
    source = source_for(conversation)
    foreign = source_for(create(:conversation))

    get path(company.id), headers: headers

    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch("task_sources").sole
    expect(item).to include("id" => source.id, "company_id" => company.id, "employee_id" => conversation.employee_id,
                            "conversation_id" => conversation.id, "local_task_id" => "task-1", "version" => 1)
    expect(item["evidence_references"]).to eq([source.evidence_references.first.slice("message_id", "turn")])
    expect(item).not_to have_key("source_snapshot")
    expect(response.body).not_to include("Raw employee transcript")
    expect(response.body).not_to include("Private aside")

    get path(company.id), params: { conversation_id: foreign.conversation_id }, headers: headers
    expect(response.parsed_body.fetch("task_sources")).to be_empty

    get path(foreign.company_id), headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "rejects unauthenticated requests" do
    get path(company.id)

    expect(response).to have_http_status(:unauthorized)
  end
end
