# frozen_string_literal: true

require "rails_helper"

# Doc 05 §4.4: management's view of the business must never reach employee
# discovery. Onboarding's share of that rule: the old questionnaire's goals and
# pain points, the revenue band, and analysis built from them stay out of every
# payload an employee interview is given. Each sentinel below sits where such
# content lives; none may appear in what the agent receives.
RSpec.describe "Employee interview context firewall" do
  let(:sentinels) do
    {
      legacy_goal: "SENTINEL-LEGACY-GOAL",
      stray_goal: "SENTINEL-STRAY-GOAL",
      revenue: "SENTINEL-REVENUE",
      questionnaire: "SENTINEL-QUESTIONNAIRE-PAIN",
      retired_knowledge: "SENTINEL-RETIRED-KNOWLEDGE"
    }
  end

  let(:company) do
    create(:company,
           company_profile: {
             "industry" => "logistics",
             "org_departments" => ["Finance"],
             # Written straight to the column, as older code did — the read side
             # must drop it even before the data migration has run.
             "business_goals" => [sentinels[:stray_goal]],
             "annual_revenue_band" => sentinels[:revenue]
           },
           legacy_profile: { "business_goals" => [sentinels[:legacy_goal]] },
           questionnaire_answers: { "q31_operational_challenges" => sentinels[:questionnaire] },
           settings: Company::DEFAULT_SETTINGS.merge("discovery_multi_agent_enabled" => true))
  end
  let(:employee) { create(:employee, company: company, department: "finance") }
  let(:conversation) do
    create(:conversation, employee: employee, status: "discovery", question_count: 1,
                          langgraph_thread_id: SecureRandom.uuid)
  end
  let(:client) { instance_double(Langgraph::Client) }

  before do
    create(:discovery_playbook, department: "finance")
    company.company_knowledge_entries.create!(entry_type: "org", title: "Old analysis",
                                              content: sentinels[:retired_knowledge], status: "superseded")
    company.company_knowledge_entries.create!(entry_type: "process", title: "Invoice SOP",
                                              content: "Invoices are matched to purchase orders.", status: "active")
    allow(Langgraph::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
  end

  it "sends the employee turn nothing onboarding keeps from staff" do
    sent = nil
    allow(client).to receive(:run_turn!) do |args|
      sent = args
      { "assistant_message" => "What does a normal Monday look like?", "insight" => {},
        "completed" => false, "question_count" => 2, "blackboard" => {} }
    end

    Discovery::ProcessTurnService.call(conversation: conversation, employee: employee,
                                       user_message: "I work in accounts payable")

    payload = sent.to_json
    sentinels.each_value { |sentinel| expect(payload).not_to include(sentinel) }
    # The firewall removes what it must and no more: confirmed facts and current
    # knowledge still reach the interview.
    expect(payload).to include("logistics", "Invoices are matched to purchase orders.")
  end

  it "keeps the same content out of the agent pack and the document-analysis snapshot" do
    [Companies::AgentContext.for_agents(company), Companies::AgentContext.docs_profile_snapshot(company)].each do |pack|
      sentinels.each_value { |sentinel| expect(pack.to_json).not_to include(sentinel) }
    end
  end
end
