# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant process clusters", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:consultant) { create(:consultant_user) }
  let(:headers) { auth_headers_for(consultant) }
  let!(:assignment) { create(:consultant_assignment, company: company, consultant_user: consultant, status: "active") }

  def path(company)
    "/api/v1/consultant/companies/#{company.id}/process_clusters"
  end

  def create_cluster(company)
    conversation = create(:conversation, employee: create(:employee, company: company))
    conversation.update!(state_snapshot: { blackboard: { dossier: { slots: {
      "how_it_works::Invoices" => { value: "Private interview wording", confidence: 0.9, turn: 2 },
      "friction_cost::Invoices" => {
        value: "Private cost wording", confidence: 0.9, turn: 3,
        effort: { effort_type: "waiting", duration: { min: 2, unit: "days", as_said: "Private effort wording" } }
      }
    } } } })
    TaskSources::SyncFromConversation.call(conversation: conversation)
    ProcessClusters::Rebuild.call(company: company).sole
  end

  it "lists company clusters and exposes historical lineage without private wording" do
    cluster = create_cluster(company)
    create_cluster(create(:company))

    get path(company), headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("process_clusters").pluck("id")).to eq([cluster.id])

    get "#{path(company)}/#{cluster.id}", params: { revision: 1 }, headers: headers
    expect(response).to have_http_status(:ok)
    record = response.parsed_body.fetch("process_cluster")
    expect(record.fetch("revision_numbers")).to eq([1])
    expect(record.fetch("memberships").sole).to include("task_source_id" => cluster.current_revision.memberships.sole.task_source_id)
    expect(record.fetch("memberships").sole.fetch("effort_observations").sole)
      .to include("duration" => { "min" => 2, "unit" => "days" })
    expect(response.body).not_to include("Private")
  end

  it "rejects unauthenticated and cross-tenant requests, including foreign IDs under an assigned company" do
    foreign = create_cluster(create(:company))

    get path(company)
    expect(response).to have_http_status(:unauthorized)
    get path(foreign.company), headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{path(company)}/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
