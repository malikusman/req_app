# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyPerson::ContextBuilder do
  let(:company) { create(:company) }
  let(:engagement) { create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY") }
  let(:participant) do
    create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Layla Haddad",
                                    role_title: "CEO", persona: "CEO_OWNER_MD", scope: "Company-wide")
  end
  let(:session) { create(:conversation_session, participant: participant, state: "COMPLETE", close_reason: "COVERAGE_COMPLETE") }

  before do
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    create(:employee, company: company, display_name: "Ahmed Saleh")
    [
      [1, "AI", "Shall we start?"],
      [2, "PARTICIPANT", "Quotes wait for my approval and we lose about 20 orders a month."],
      [3, "AI", "What would make this worthwhile?"],
      [4, "PARTICIPANT", "Quotes going out the same day. Again — the approvals are the biggest issue."],
      [5, "PARTICIPANT", "We move to a new ERP next year, maybe in March. Ahmed is always late with the figures."]
    ].each do |index, direction, text|
      capture = direction == "PARTICIPANT" ? { "statements" => [{ "domain" => "DECISIONS_APPROVALS", "statement" => text, "evidence" => "t#{index}" }], "planned_initiatives" => [], "political_signals" => [], "sensitive" => [] } : nil
      create(:conversation_turn, session: session, turn_index: index, direction: direction, text: text, capture: capture)
    end
  end

  def build(reply)
    replies = reply.is_a?(Array) ? reply : [reply]
    described_class.call(session, client: KeyPersonFakeClient.new(contexts: replies))
  end

  let(:reply) do
    {
      "management_context" => {
        "persona" => "CEO_OWNER_MD", "scope" => "Company-wide",
        "decision_structure" => [{ "text" => "Quotes wait for the owner's approval.", "evidence" => %w[t2 t4 t9] }],
        "concerns" => [{ "text" => "Orders are lost.", "evidence" => [] }],
        "success_definition" => { "text" => "Quotes going out the same day.", "evidence" => ["t4"] },
        "change_appetite_inferred" => { "level" => "HIGH", "basis" => "Keen", "fact_status" => "REPORTED" }
      },
      "strategic_findings" => [
        { "category" => "DECISIONS_APPROVALS", "scope" => "COMPANY",
          "statement" => "Many quotations wait for the owner's personal approval.", "symptom_or_cause" => "SUSPECTED_CAUSE",
          "source_basis" => "MANAGEMENT_STATEMENT", "fact_status" => "VERIFIED", "management_importance" => "HIGH",
          "validation_need" => "Check with sales staff how often quotes wait.", "evidence" => %w[t2 t4] },
        { "category" => "PROCESS", "statement" => "Ahmed is late with the monthly figures.", "evidence" => ["t5"] },
        { "category" => "AUTOMATION", "statement" => "The company should implement an AI agent for quotes.",
          "evidence" => ["t2"] },
        { "category" => "GROWTH", "statement" => "The company loses 45 orders a month.", "evidence" => ["t2"] },
        { "category" => "GROWTH", "statement" => "The company loses about 20 orders a month to slow quotes.",
          "evidence" => ["t2"] },
        { "category" => "RISK", "statement" => "Uncited.", "evidence" => [] }
      ],
      "planned_initiatives" => [{ "type" => "ERP", "description" => "Move to a new ERP", "timing" => "next year",
                                  "status" => "PROPOSED", "evidence" => ["t5"] }],
      "neutral_context_for_employee_discovery" => [
        { "department" => "Sales", "context" => "The company is working to send quotations to customers more quickly." },
        { "department" => "Sales", "context" => "Management thinks sales staff are too slow." },
        { "department" => "Finance", "context" => "Ahmed's figures will be reviewed." },
        { "department" => "Finance", "context" => "The company plans to adopt AI for reporting." },
        { "department" => "Company", "context" => "The business plans to move to a new ERP." }
      ],
      "political_context" => { "decision_makers" => [{ "note" => "The owner decides on pricing.", "evidence" => ["t2"] }] },
      "unknowns" => [{ "domain" => "CONSTRAINTS", "note" => "Not discussed" }],
      "contradictions" => [{ "between" => "ERP timing", "note" => "Said next year, then March.", "evidence" => ["t5"] }],
      "completion" => { "domains_adequate" => %w[DECISIONS_APPROVALS NOT_A_DOMAIN], "confidence" => "MEDIUM" }
    }
  end

  it "keeps what validates and links every item to real turns" do
    context = build(reply)

    expect(context).to have_attributes(status: "COMPLETE", version: 1, prompt_version: "P04.v1", persona: "CEO_OWNER_MD")
    expect(context.content["decision_structure"]).to eq([{ "text" => "Quotes wait for the owner's approval.",
                                                           "evidence" => %w[t2 t4] }])
    expect(context.content["concerns"]).to eq([])
    expect(context.content["change_appetite_inferred"]).to include("level" => "HIGH", "fact_status" => "INFERRED")
    expect(context.completion).to eq("domains_adequate" => ["DECISIONS_APPROVALS"], "domains_thin" => [],
                                     "confidence" => "MEDIUM")
    expect(AiRun.last).to have_attributes(stage: "P04", status: "OK")
  end

  it "writes findings as reported observations, never naming, prescribing or inventing (P04 §11)" do
    findings = build(reply).strategic_findings.order(:id)

    expect(findings.map(&:statement)).to eq(["Many quotations wait for the owner's personal approval.",
                                             "The company loses about 20 orders a month to slow quotes."])
    expect(findings.first).to have_attributes(category: "GOVERNANCE", fact_status: "REPORTED",
                                              management_importance: "HIGH", evidence: %w[t2 t4])
  end

  it "passes on only neutral context that can't bias staff" do
    context = build(reply)

    expect(context.neutral_employee_context).to eq([
                                                     { "department" => "Sales", "context" => "The company is working to send quotations to customers more quickly." },
                                                     { "department" => "Company", "context" => "The business plans to move to a new ERP." }
                                                   ])
    expect(Companies::AgentContext.neutral_management_context(company, department: "sales"))
      .to eq(["The company is working to send quotations to customers more quickly.",
              "The business plans to move to a new ERP."])
    expect(Companies::AgentContext.neutral_management_context(company, department: "Finance"))
      .to eq(["The business plans to move to a new ERP."])
  end

  it "keeps political context for consultants only, and the initiatives as records" do
    context = build(reply)

    expect(context.consultant_private.dig("political_context", "decision_makers"))
      .to eq([{ "note" => "The owner decides on pricing.", "evidence" => ["t2"] }])
    expect(context.content.to_json).not_to include("decides on pricing")
    expect(context.planned_initiatives.first).to have_attributes(initiative_type: "ERP", status: "PROPOSED",
                                                                 evidence: ["t5"])
  end

  it "builds an incomplete record from the captures when P04 can't be used (P04 §9)" do
    context = build(["not json", "still not json"])

    expect(context).to have_attributes(status: "INCOMPLETE", fallback_reason: "unusable_reply")
    expect(context.content["decision_structure"].size).to eq(3)
    expect(context.strategic_findings).to be_empty
    expect(context.neutral_employee_context).to eq([])
    expect(session.reload.needs_review).to be(true)
    expect(session.review_reasons).to include({ "type" => "CONTEXT_INCOMPLETE" })
  end

  it "makes one context per session, and a new version for a further session" do
    first = build(reply)
    expect(build(reply)).to eq(first)

    later = create(:conversation_session, participant: participant, version: 2, state: "COMPLETE")
    create(:conversation_turn, session: later, turn_index: 1, text: "Quotes still wait for me.")
    second = described_class.call(later, client: KeyPersonFakeClient.new(contexts: [reply]))

    expect(second).to have_attributes(version: 2, parent_version: first)
    expect(ManagementDiscoveryContext.where(engagement: engagement).latest_per_participant).to eq([second])
  end

  it "runs after a conversation finishes" do
    expect { KeyPerson::Completion.call(session) }.to have_enqueued_job(KeyPersonContextJob).with(session.id)
  end
end
