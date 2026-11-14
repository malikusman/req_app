# frozen_string_literal: true

require "rails_helper"

# What a consultant sees of, and does about, the conversations with leadership.
RSpec.describe "Consultant view of the leadership conversations", type: :request do
  include ActiveJob::TestHelper

  let(:consultant) { create(:consultant_user) }
  let(:headers) { auth_headers_for(consultant) }
  let(:company) { create(:company) }
  let(:key_user) { create(:company_user, company: company, name: "Layla Haddad", job_title: "CEO") }
  let!(:engagement) do
    create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY", key_user: key_user, lead_consultant: consultant,
                        planned_departments: [{ "name" => "Sales", "count" => "UNKNOWN" }])
  end
  let(:path) { "/api/v1/consultant/companies/#{company.id}/leadership" }
  let(:own) { engagement.participants.find_by!(source: "KEY_USER") }
  let(:manager) do
    create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Rania Saleh",
                                    role_title: "Head of Sales", email: "rania@client.example")
  end

  before do
    create(:consultant_assignment, consultant_user: consultant, company: company, status: "active")
    allow(Openai::Client).to receive(:new).and_return(KeyPersonFakeClient.scripted)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    manager
    KeyPerson::Kickoff.call(engagement)
  end

  def finished_context
    session = create(:conversation_session, participant: own, state: "COMPLETE", close_reason: "COVERAGE_COMPLETE",
                                            state_snapshot: { "coverage" => { "CONCERNS" => { "status" => "USABLE" } } })
    create(:conversation_turn, session: session, turn_index: 1, text: "Quotes wait for my approval.",
                               capture: { "sensitive" => [{ "type" => "PERSONAL", "note" => "SENTINEL-NOTE" }] })
    context = ManagementDiscoveryContext.create!(
      company: company, engagement: engagement, participant: own, session: session, status: "COMPLETE",
      schema_version: "MDC.v1", consultant_private: { "political_context" => { "decision_makers" => [{ "note" => "Owner decides" }] } }
    )
    context.strategic_findings.create!(company: company, engagement: engagement, category: "GOVERNANCE", scope: "COMPANY",
                                       statement: "Quotes wait for the owner's approval.", source_basis: "MANAGEMENT_STATEMENT",
                                       fact_status: "REPORTED", evidence: ["t1"])
  end

  it "shows everyone taking part, coverage, what was produced, and the consultant-only parts" do
    finding = finished_context

    get path, headers: headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["participants"].pluck("name")).to eq(["Layla Haddad", "Rania Saleh"])
    layla = body["participants"].first
    expect(layla["sessions"].first["coverage"]).to include("CONCERNS" => "USABLE", "AMBITION" => "OPEN")
    expect(layla["sessions"].first["transcript"].first["capture"]).to be_present
    expect(layla["contexts"].first["findings"].pluck("id")).to eq([finding.id])
    expect(layla["contexts"].first["consultant_private"]).to be_present
  end

  it "is only for consultants assigned to the company" do
    get path, headers: auth_headers_for(create(:consultant_user))
    expect(response).to have_http_status(:not_found)
  end

  it "sets a persona and a neutral focus" do
    patch "#{path}/participants/#{manager.id}", params: { participant: { persona: "SALES_COMMERCIAL",
                                                                        consultant_focus: "Quotation speed" } },
                                                headers: headers, as: :json
    expect(manager.reload).to have_attributes(persona: "SALES_COMMERCIAL", consultant_focus: "Quotation speed")
  end

  it "corrects a finding as a new version, keeping the old one" do
    finding = finished_context

    patch "#{path}/findings/#{finding.id}", params: { finding: { statement: "Most quotes wait for approval." },
                                                      rationale: "Owner clarified on a call" },
                                            headers: headers, as: :json

    expect(finding.reload.status).to eq("SUPERSEDED")
    corrected = StrategicFinding.find_by!(parent_version_id: finding.id)
    expect(corrected).to have_attributes(statement: "Most quotes wait for approval.", version: 2, status: "ACTIVE",
                                         edited_by: consultant, edit_rationale: "Owner clarified on a call")
  end

  it "rejects a finding with a reason, and keeps it" do
    finding = finished_context
    patch "#{path}/findings/#{finding.id}", params: { reject: true, rationale: "" }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    patch "#{path}/findings/#{finding.id}", params: { reject: true, rationale: "Not what was said" }, headers: headers, as: :json
    expect(finding.reload).to have_attributes(status: "REJECTED", edit_rationale: "Not what was said")
  end

  it "closes a conversation that won't finish, builds its context, and lets pricing go ahead" do
    session = create(:conversation_session, participant: own, state: "BROAD_DISCOVERY")
    create(:conversation_turn, session: session, turn_index: 1, text: "We want to grow.",
                               capture: { "statements" => [{ "domain" => "STRATEGIC_OBJECTIVES", "statement" => "Wants to grow.", "evidence" => "t1" }] })
    engagement.update!(planned_departments: [{ "name" => "Sales", "count" => 2 }])

    # P24 isn't what this is about; the fake model here only speaks for P02–P04.
    perform_enqueued_jobs(except: ExplainStage1QuoteJob) { post "#{path}/participants/#{own.id}/close", headers: headers }

    expect(session.reload).to have_attributes(state: "ABANDONED", close_reason: "ABANDONED")
    expect(own.reload.participation_status).to eq("ABANDONED")
    expect(session.management_discovery_context).to be_present
    expect(engagement.reload.status).to eq("STAGE_1_PRICING")
  end

  it "opens a further session that carries on from the coverage so far" do
    finished_context
    perform_enqueued_jobs { post "#{path}/participants/#{own.id}/further_session", headers: headers }

    expect(response).to have_http_status(:created)
    latest = own.conversation_sessions.last
    expect(latest).to have_attributes(version: 2, state: "NOT_STARTED")
    expect(latest.state_snapshot.dig("coverage", "CONCERNS", "status")).to eq("USABLE")
    expect(own.reload.participation_status).to eq("INVITED")
  end

  it "settles planned counts agreed with the client" do
    patch "#{path}/plan", params: { departments: [{ name: "Sales", count: 4 }] }, headers: headers, as: :json
    expect(engagement.reload.planned_participant_count).to eq(4)
  end

  it "hands over to pricing as the consultant once the plan is settled" do
    create(:conversation_session, participant: own, state: "COMPLETE")
    patch "#{path}/plan", params: { departments: [{ name: "Sales", count: 4 }] }, headers: headers, as: :json

    expect(engagement.reload.status).to eq("STAGE_1_PRICING")
    expect(engagement.status_history.last).to include("by_type" => "ConsultantUser", "by_id" => consultant.id)
  end

  it "sends an invitation again with a fresh link" do
    old = manager.reload.access_token_digest
    perform_enqueued_jobs { post "#{path}/participants/#{manager.id}/invite", headers: headers }
    expect(manager.reload.access_token_digest).not_to eq(old)
  end
end
