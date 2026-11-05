# frozen_string_literal: true

require "rails_helper"

# Doc 08 §18, §27; Doc 05 §4.4: what management says in the conversations with
# leadership must never reach employee discovery, and one manager's words must
# never reach another, or the client portal. Each sentinel below sits where the
# conversations keep something; none may appear where it mustn't.
#
# The one sanctioned route to staff is the neutral context, checked when it was
# written and read through Companies::AgentContext.neutral_management_context.
RSpec.describe "Leadership conversation firewall", type: :request do
  let(:sentinels) do
    {
      key_user_turn: "SENTINEL-KEY-USER-SAID",
      manager_turn: "SENTINEL-MANAGER-SAID",
      sensitive: "SENTINEL-SENSITIVE-NOTE",
      political_capture: "SENTINEL-POLITICAL-CAPTURE",
      context_content: "SENTINEL-CONTEXT-CONCERN",
      political_context: "SENTINEL-POLITICAL-CONTEXT",
      consultant_note: "SENTINEL-CONSULTANT-NOTE",
      finding: "SENTINEL-FINDING",
      initiative: "SENTINEL-INITIATIVE",
      document_request: "SENTINEL-DOCUMENT-REQUEST",
      document_text: "SENTINEL-KPI-PACK",
      document_name: "SENTINEL-FILENAME",
      contradiction: "SENTINEL-CONTRADICTION"
    }
  end
  let(:neutral_line) { "The company wants to respond to customer enquiries faster." }

  let(:company) do
    create(:company, company_profile: { "industry" => "logistics", "org_departments" => ["Finance"] },
                     settings: Company::DEFAULT_SETTINGS.merge("discovery_multi_agent_enabled" => true))
  end
  let(:key_user) { create(:company_user, company: company, name: "Layla Haddad", job_title: "CEO") }
  let!(:engagement) do
    create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY", key_user: key_user,
                        planned_departments: [{ "name" => "Finance", "count" => 2 }])
  end
  let(:manager) do
    create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Rania Saleh",
                                    email: "rania@client.example")
  end
  let(:storage) { instance_double(Storage::MinioClient, upload: true) }

  before do
    stub_request(:get, %r{http://gotenberg:3000/health}).to_return(status: 200, body: "")
    allow(Storage::MinioClient).to receive(:new).and_return(storage)
    allow(Openai::Client).to receive(:new).and_return(KeyPersonFakeClient.scripted)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    manager
    KeyPerson::Kickoff.call(engagement)
    plant!(engagement.participants.find_by!(source: "KEY_USER"), sentinels[:key_user_turn])
    plant!(manager, sentinels[:manager_turn])
  end

  # A finished conversation with everything it can leave behind.
  def plant!(participant, said)
    participant.update!(consent_recorded_at: Time.current, participation_status: "COMPLETED")
    session = create(:conversation_session, participant: participant, state: "COMPLETE",
                                            state_snapshot: { "contradictions" => [{ "field" => "industry", "value" => sentinels[:contradiction] }],
                                                              "summary" => [{ "area" => "CONCERNS", "text" => said }] })
    create(:conversation_turn, session: session, turn_index: 1, direction: "AI", text: "Shall we start?")
    create(:conversation_turn, session: session, turn_index: 2, text: said,
                               capture: { "sensitive" => [{ "type" => "CRITICISM_OF_PERSON", "note" => sentinels[:sensitive] }],
                                          "political_signals" => [{ "note" => sentinels[:political_capture] }] })
    context = ManagementDiscoveryContext.create!(
      company: company, engagement: engagement, participant: participant, session: session, status: "COMPLETE",
      schema_version: "MDC.v1",
      content: { "concerns" => [{ "text" => sentinels[:context_content], "evidence" => ["t2"] }] },
      neutral_employee_context: [{ "department" => "Finance", "context" => neutral_line }],
      consultant_private: { "political_context" => { "decision_makers" => [{ "note" => sentinels[:political_context] }] },
                            "consultant_notes" => [{ "type" => "SENSITIVE", "note" => sentinels[:consultant_note] }] }
    )
    context.strategic_findings.create!(company: company, engagement: engagement, category: "GOVERNANCE", scope: "COMPANY",
                                       statement: sentinels[:finding], source_basis: "MANAGEMENT_STATEMENT",
                                       fact_status: "REPORTED", evidence: ["t2"])
    context.planned_initiatives.create!(company: company, engagement: engagement, initiative_type: "ERP",
                                        description: sentinels[:initiative], status: "PROPOSED", evidence: ["t2"])
    request = DocumentRequest.create!(company: company, session: session, requested_item: sentinels[:document_request],
                                      reason: "Mentioned")
    file = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 #{sentinels[:document_text]}"), "application/pdf",
                                        original_filename: "#{sentinels[:document_name]}.pdf")
    KeyPerson::Documents.new(session).upload!(file, request_id: request.id)
  end

  def expect_clean(payload, except: [])
    text = payload.is_a?(String) ? payload : payload.to_json
    sentinels.except(*except).each_value { |sentinel| expect(text).not_to include(sentinel) }
  end

  describe "employee discovery" do
    let(:employee) { create(:employee, company: company, department: "finance") }
    let(:conversation) do
      create(:conversation, employee: employee, status: "discovery", question_count: 1, langgraph_thread_id: SecureRandom.uuid)
    end
    let(:client) { instance_double(Langgraph::Client) }

    before do
      create(:discovery_playbook, department: "finance")
      allow(Langgraph::Client).to receive(:new).and_return(client)
    end

    it "sends the employee turn nothing from the conversations with leadership" do
      sent = nil
      allow(client).to receive(:run_turn!) do |args|
        sent = args
        { "assistant_message" => "What does a normal Monday look like?", "insight" => {}, "completed" => false,
          "question_count" => 2, "blackboard" => {} }
      end

      Discovery::ProcessTurnService.call(conversation: conversation, employee: employee, user_message: "I pay invoices")

      expect_clean(sent)
      expect(sent.to_json).to include("logistics")
    end

    it "never turns a leadership upload into something the interview can read" do
      documents = company.documents.leadership
      expect(documents.count).to eq(2)
      expect(documents.pluck(:status).uniq).to eq(["uploaded"])
      expect(DocumentChunk.where(document_id: documents.select(:id))).to be_empty
      expect do
        Documents::StartAnalysisRunService.call(company: company, user: key_user, run_kind: "incremental_docs",
                                                document_ids: documents.pluck(:id))
      end.to raise_error(Documents::StartAnalysisRunService::Error, /No documents awaiting analysis/)
    end

    it "keeps it out of the agent pack and the document-analysis snapshot" do
      expect_clean(Companies::AgentContext.for_agents(company))
      expect_clean(Companies::AgentContext.docs_profile_snapshot(company))
    end

    it "passes on only the checked neutral line" do
      lines = Companies::AgentContext.neutral_management_context(company, department: "Finance")
      expect(lines).to eq([neutral_line])
      expect_clean(lines)
    end
  end

  describe "the client portal" do
    let(:headers) { auth_headers_for(key_user) }

    it "shows the key user the managers' status on the dashboard, nothing they said" do
      get "/api/v1/company/dashboard", headers: headers
      expect(response).to have_http_status(:ok)
      expect_clean(response.body)
    end

    it "keeps leadership uploads out of the company's documents" do
      get "/api/v1/company/documents", headers: headers
      expect_clean(response.body)
    end

    it "shows the key user their own words, and nothing captured from them or anyone else" do
      get "/api/v1/company/leadership", headers: headers
      expect(response.body).to include(sentinels[:key_user_turn])
      expect_clean(response.body, except: %i[key_user_turn document_request])
    end

    it "shows a manager their own words by their link, and nothing of the key user's" do
      token = KeyPerson::Invite.new(manager.reload).link![%r{/leadership/(.+)\z}, 1]
      get "/api/v1/public/leadership/#{token}"
      expect(response.body).to include(sentinels[:manager_turn])
      expect_clean(response.body, except: %i[manager_turn document_request])
    end
  end

  it "shows the platform how far each conversation got, never what was said" do
    get "/api/v1/platform/companies/#{company.id}", headers: auth_headers_for(create(:platform_user))
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rania Saleh")
    expect_clean(response.body)
  end
end
