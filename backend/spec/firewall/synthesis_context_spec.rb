# frozen_string_literal: true

require "rails_helper"

# Doc 10 §22, Doc 05 §4 and P11 §4: synthesis reads across participants and
# leadership, so what it produces must stay where only consultants see it.
#
#   - What is consultant-private never reaches P10 or P11, so it can never come
#     out of them.
#   - Nothing synthesis wrote reaches an employee's interview, the agent pack,
#     the neutral line to staff, or anything the client or a manager can open.
#   - A reply that names someone is stripped before it is stored.
#
# Each sentinel below is planted where synthesis keeps something; none may
# appear where it mustn't. The consultant's view is the positive control.
RSpec.describe "Synthesis firewall", type: :request do
  let(:sentinels) do
    {
      political: "SENTINEL-POLITICAL-CONTEXT",
      consultant_note: "SENTINEL-CONSULTANT-NOTE",
      relationship: "SENTINEL-RELATIONSHIP-RATIONALE",
      opportunity: "SENTINEL-OPPORTUNITY",
      root_cause: "SENTINEL-ROOT-CAUSE",
      verdict: "SENTINEL-VERDICT",
      picture: "SENTINEL-OPERATING-PICTURE",
      role_potential: "SENTINEL-ROLE-POTENTIAL"
    }
  end
  let(:outputs) { sentinels.except(:political, :consultant_note) }
  let(:neutral_line) { "The company wants to respond to customer enquiries faster." }

  let(:company) do
    create(:company, :onboarded, company_profile: { "industry" => "logistics", "org_departments" => ["Sales"] },
                                 settings: Company::DEFAULT_SETTINGS.merge("discovery_multi_agent_enabled" => true))
  end
  let(:key_user) { create(:company_user, company: company, name: "Layla Haddad", job_title: "CEO") }
  let!(:engagement) { create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY", key_user: key_user) }
  let(:storage) { instance_double(Storage::MinioClient, upload: true) }
  let(:fake) do
    SynthesisFakeClient.new(
      relationships: [->(_) { relationship_reply }],
      syntheses: [->(context) { synthesis_reply(context) }]
    )
  end

  let!(:quotes) do
    synthesis_finding(company: company, role: "Sales Coordinator", title: "Preparing quotes",
                      what_happens_now: "Check stock and the price list, fill the quotation template, email it",
                      hours: [100, 150])
  end
  let!(:quotes_again) do
    synthesis_finding(company: company, role: "Sales Coordinator", title: "Preparing quotes",
                      what_happens_now: "Check stock and the price list, fill the quotation template, email it",
                      hours: [80, 120])
  end
  let!(:concern) do
    context = leadership_context(
      engagement: engagement, name: "Layla Haddad",
      content: { "concerns" => [{ "text" => "Quotes take too long", "evidence" => ["t2"] }] },
      consultant_private: { "political_context" => { "decision_makers" => [{ "note" => sentinels[:political] }] },
                            "consultant_notes" => [{ "type" => "SENSITIVE", "note" => sentinels[:consultant_note] }] }
    )
    context.update!(neutral_employee_context: [{ "department" => "Sales", "context" => neutral_line }])
    strategic_finding(context, statement: "Quotes take too long", importance: "HIGH")
  end

  def relationship_reply
    { "relationship" => "SAME_PROCESS", "confidence" => "MEDIUM", "recommendation" => "PROVISIONAL_CLUSTER",
      "evidence_for" => ["Same quotation work"], "effort_overlap" => { "same_execution" => "NO", "note" => "Own customers" },
      "rationale" => sentinels[:relationship] }
  end

  def synthesis_reply(context)
    cluster = context[/"ref": "(cl-[\w-]+)"/, 1]
    {
      "operating_picture" => { "how_the_business_runs" => sentinels[:picture], "departments" => [],
                               "evidence" => ["wi_#{quotes.id}"] },
      "root_causes" => [{ "statement" => "#{sentinels[:root_cause]} prices are kept apart",
                          "explains" => ["wi_#{quotes.id}", "wi_#{quotes_again.id}"], "confidence" => "MEDIUM",
                          "fact_status" => "INFERRED", "evidence" => [] }],
      "opportunities" => [{
        "title" => sentinels[:opportunity], "level" => "SHARED_TASK", "category" => "PROCESS",
        "problem_statement" => "Quotes are prepared separately by each coordinator.",
        "affected_clusters" => [cluster].compact, "management_alignment" => "Layla Haddad wants faster quotes.",
        "recommended_next_action" => "DEEP_DIVE", "confidence" => "MEDIUM",
        "evidence" => ["wi_#{quotes.id}", "sf_#{concern.id}"]
      }],
      "management_versus_evidence" => [{ "management_view" => "Quotes take too long", "relationship" => "SUPPORTED",
                                         "what_evidence_shows" => sentinels[:verdict], "evidence" => ["sf_#{concern.id}"] }],
      "role_potential_summary" => [{ "role" => "Sales Coordinator", "potential_focus" => [sentinels[:role_potential]],
                                     "basis" => "PARTICIPANT" }],
      "confidence" => "MEDIUM"
    }
  end

  before do
    stub_request(:get, %r{http://gotenberg:3000/health}).to_return(status: 200, body: "")
    allow(Storage::MinioClient).to receive(:new).and_return(storage)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    run = SynthesisRun.create!(company: company, engagement: engagement, version: 1, trigger: "MANUAL",
                               requested_at: Time.current)
    Synthesis::Run.call(run, client: fake)
  end

  def expect_clean(payload, keys: sentinels.keys)
    text = payload.is_a?(String) ? payload : payload.to_json
    sentinels.slice(*keys).each_value { |sentinel| expect(text).not_to include(sentinel) }
  end

  it "plants every output where synthesis keeps it (the consultant sees them)" do
    view = Synthesis::ConsultantView.new(engagement).json.to_json
    outputs.each_value { |sentinel| expect(view).to include(sentinel) }
  end

  it "never sends what is consultant-private, or a name, to P10 or P11" do
    contexts = fake.calls.map { |c| c[:context] }
    expect(contexts.size).to eq(2)
    expect_clean(contexts, keys: %i[political consultant_note])
    expect(contexts.join).not_to include("Layla")
  end

  it "strips a reply that names someone before anything is stored" do
    stored = ConsultancyOpportunity.sole
    expect(stored.title).to eq(sentinels[:opportunity])
    expect(stored.management_alignment).to be_nil
    expect(ConsultancyOpportunity.pluck(:management_alignment, :problem_statement).flatten.join).not_to include("Layla")
  end

  describe "employee discovery" do
    let(:employee) { create(:employee, company: company, department: "Sales") }
    let(:conversation) do
      create(:conversation, employee: employee, status: "discovery", question_count: 1, langgraph_thread_id: SecureRandom.uuid)
    end
    let(:client) { instance_double(Langgraph::Client) }

    before do
      create(:discovery_playbook, department: "Sales")
      allow(Langgraph::Client).to receive(:new).and_return(client)
    end

    it "sends the employee turn nothing synthesis produced" do
      sent = nil
      allow(client).to receive(:run_turn!) do |args|
        sent = args
        { "assistant_message" => "What does a normal Monday look like?", "insight" => {}, "completed" => false,
          "question_count" => 2, "blackboard" => {} }
      end

      Discovery::ProcessTurnService.call(conversation: conversation, employee: employee, user_message: "I prepare quotes")

      expect(sent).to be_present
      expect_clean(sent)
    end

    it "keeps it out of the agent pack, the document-analysis snapshot and the neutral line" do
      expect_clean(Companies::AgentContext.for_agents(company))
      expect_clean(Companies::AgentContext.docs_profile_snapshot(company))
      lines = Companies::AgentContext.neutral_management_context(company, department: "Sales")
      expect(lines).to eq([neutral_line])
    end
  end

  describe "the client portal" do
    let(:headers) { auth_headers_for(key_user) }

    before do
      allow(Openai::Client).to receive(:new).and_return(KeyPersonFakeClient.scripted)
      KeyPerson::Kickoff.call(engagement)
    end

    it "shows the key user nothing synthesis produced, however far it got" do
      ConsultancyOpportunity.sole.revise!(status: "APPROVED")
      %w[/api/v1/company/dashboard /api/v1/company/leadership /api/v1/company/documents].each do |path|
        get path, headers: headers
        expect(response).to have_http_status(:ok), path
        expect_clean(response.body)
      end
    end
  end

  it "shows the platform nothing synthesis produced" do
    get "/api/v1/platform/companies/#{company.id}", headers: auth_headers_for(create(:platform_user))
    expect(response).to have_http_status(:ok)
    expect_clean(response.body)
  end

  it "keeps a manager's own link to their own conversation" do
    manager = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Rania Saleh",
                                              email: "rania@client.example")
    allow(Openai::Client).to receive(:new).and_return(KeyPersonFakeClient.scripted)
    KeyPerson::Kickoff.call(engagement)
    token = KeyPerson::Invite.new(manager.reload).link![%r{/leadership/(.+)\z}, 1]
    get "/api/v1/public/leadership/#{token}"
    expect_clean(response.body)
  end
end
