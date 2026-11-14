# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant Task Intelligence", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:consultant) { create(:consultant_user) }
  let(:headers) { auth_headers_for(consultant) }
  let!(:assignment) { create(:consultant_assignment, company: company, consultant_user: consultant, status: "active") }

  def path(company)
    "/api/v1/consultant/companies/#{company.id}/task_intelligence_runs"
  end

  def generate(company)
    conversation = create(:conversation, employee: create(:employee, company: company))
    conversation.update!(state_snapshot: { blackboard: { dossier: { slots: {
      "how_it_works::Invoices" => { value: "Private invoice transcript", confidence: 0.9, turn: 2 },
      "how_it_works::Tax" => { value: "Private payroll transcript", confidence: 0.9, turn: 3 }
    } } } })
    TaskSources::SyncFromConversation.call(conversation: conversation)
    ProcessClusters::Rebuild.call(company: company)
    TaskIntelligence::Generate.call(company: company, target: 1)
  end

  it "returns run history, shortlist, every disposition and scoped evidence metadata" do
    run = generate(company)

    get path(company), headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("task_intelligence_runs").sole).to include(
      "id" => run.id, "evaluation_mode" => "deterministic", "evaluation_limitation" => include("Semantic AI")
    )

    get "#{path(company)}/#{run.id}", headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body.fetch("task_intelligence_run")
    expect(body.fetch("shortlist").sole).to include("rank" => 1)
    expect(body.fetch("dispositions").sole).to include("disposition" => "deferred_capacity")
    candidate = run.candidates.find_by!(rank: 1)

    get "#{path(company)}/#{run.id}/candidates/#{candidate.id}", headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body.fetch("task_candidate")
    expect(body).to include("process_cluster_revision_id" => candidate.process_cluster_revision_id, "confidence" => "low")
    expect(body.fetch("assessment").fetch("evidence_sources").sole).to include("source_version" => 1)
    expect(response.body).not_to include("Private")
  end

  it "requires consultant authentication and scopes runs and candidate IDs to the requested company" do
    own = generate(company)
    foreign = generate(create(:company))

    get path(company)
    expect(response).to have_http_status(:unauthorized)
    get path(foreign.company), headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{path(company)}/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{path(company)}/#{own.id}/candidates/#{foreign.candidates.first.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
