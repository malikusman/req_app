# frozen_string_literal: true

require "rails_helper"

# P11 §3–§4, §9–§10; Doc 10 §15: synthesis reads leadership and staff evidence
# together but never what is consultant-private, never a transcript and never
# a name; it stores only what passes the checks; management importance and
# platform priority stay apart; and a consultant's decisions survive re-runs.
RSpec.describe Synthesis::Synthesizer do
  let(:company) { create(:company, :onboarded, company_profile: { "industry" => "trading", "org_departments" => %w[Sales Procurement] }) }
  let(:engagement) { create(:engagement, company: company) }
  let(:run) do
    SynthesisRun.create!(company: company, engagement: engagement, version: 1, trigger: "MANUAL",
                         requested_at: Time.current, status: "RUNNING")
  end
  let(:sales_employee) { create(:employee, company: company, display_name: "Omar Siddiqui", role_title: "Sales Coordinator", department: "Sales") }
  let!(:quotes) do
    synthesis_finding(company: company, employee: sales_employee, role: "Sales Coordinator", title: "Preparing quotes",
                      what_happens_now: "Prices are copied from the supplier sheet into each quotation",
                      hours: [130, 170])
  end
  let!(:price_entry) do
    synthesis_finding(company: company, role: "Buyer", department: "Procurement", title: "Supplier price entry",
                      what_happens_now: "Supplier price sheets are keyed into the ERP by hand", hours: [80, 120])
  end
  let(:context) do
    leadership_context(engagement: engagement, name: "Layla Haddad",
                       content: { "concerns" => [{ "text" => "Pricing errors reach customers", "evidence" => ["t2"] }],
                                  "released_time_preferences" => [{ "role_or_team" => "Sales", "preferred_focus" => "Key accounts" }] },
                       consultant_private: { "political_context" => { "resistance_points" => [{ "note" => "SENTINEL-POLITICS" }] } })
  end
  let!(:pricing_concern) { strategic_finding(context, statement: "Pricing errors reach customers", importance: "HIGH") }
  let!(:finance_concern) { strategic_finding(context, statement: "Finance closes the month late", importance: "MEDIUM") }

  before { allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false) }

  def items = Synthesis::WorkItems.call(company)

  def reply(**overrides)
    {
      "operating_picture" => {
        "how_the_business_runs" => "Sales quotes from supplier prices that procurement keys into the ERP.",
        "departments" => [{ "name" => "Sales", "what_it_does" => "Quotes customers", "main_systems" => ["ERP"] }],
        "work_flows_between" => [{ "from" => "Procurement", "to" => "Sales", "what_moves" => "Prices", "how" => "Spreadsheet" }],
        "where_information_lives" => ["Supplier sheets"], "ai_and_automation_in_use" => [], "evidence" => ["wi_#{quotes.id}"]
      },
      "root_causes" => [{
        "statement" => "Prices are kept in several places, so the same data is re-entered.",
        "explains" => ["wi_#{quotes.id}", "wi_#{price_entry.id}"], "affected_departments" => %w[Sales Procurement],
        "supporting_signals" => ["Both re-key supplier prices"], "fact_status" => "CONFIRMED", "confidence" => "MEDIUM",
        "what_would_confirm_it" => "Whether the ERP can import supplier sheets.", "evidence" => ["sf_#{pricing_concern.id}"]
      }],
      "opportunities" => [{
        "title" => "One source of truth for product prices", "level" => "CROSS_DEPARTMENT", "category" => "INTEGRATION",
        "problem_statement" => "Prices are maintained by procurement and sales separately, so errors reach customers.",
        "evidence_summary" => "Two roles re-key the same prices.",
        "affected_clusters" => [], "affected_departments" => %w[Sales Procurement],
        "root_cause_ref" => "Prices are kept in several places",
        "capacity_reference" => "Preparing quotes: 130–170 hours per year", "other_value" => %w[QUALITY SERVICE],
        "intervention_direction" => "Establish one authoritative price source and feed the others from it.",
        "ai_relevance" => "SUPPORTING", "ai_note" => "AI could normalise supplier sheet formats.",
        "management_alignment" => "Management raised pricing errors.", "planned_initiative_conflict" => nil,
        "dependencies" => [], "recommended_next_action" => "DEEP_DIVE", "priority_reason" => "Three departments.",
        "confidence" => "MEDIUM", "evidence" => ["wi_#{quotes.id}", "wi_#{price_entry.id}", "sf_#{pricing_concern.id}"]
      }],
      "management_versus_evidence" => [
        { "management_view" => "Pricing errors reach customers", "what_evidence_shows" => "Two roles re-key prices by hand.",
          "relationship" => "SUPPORTED", "note" => "Borne out.", "evidence" => ["sf_#{pricing_concern.id}", "wi_#{quotes.id}"] },
        { "management_view" => "Finance closes the month late", "what_evidence_shows" => "Approvals wait on sales.",
          "relationship" => "POINTS_ELSEWHERE", "note" => "Symptom right, cause elsewhere.", "evidence" => ["sf_#{finance_concern.id}"] }
      ],
      "initiative_conflicts" => [],
      "role_potential_summary" => [{ "role" => "Sales Coordinator", "department" => "Sales",
                                     "potential_focus" => ["Key accounts"], "basis" => "BOTH", "evidence" => [] }],
      "coverage_notes" => [{ "note" => "Finance not yet interviewed." }],
      "confidence" => "MEDIUM"
    }.merge(overrides)
  end

  def synthesise(*replies, clusters: [])
    client = SynthesisFakeClient.new(syntheses: replies)
    outcome = described_class.call(run: run, items: items, clusters: clusters, client: client)
    [outcome, client]
  end

  describe "what reaches the model" do
    it "carries leadership and staff evidence, but nothing consultant-private, no transcript and no names" do
      _, client = synthesise(reply)
      context = client.contexts(:synthesis).first

      expect(context).to include("Pricing errors reach customers", "sf_#{pricing_concern.id}", "wi_#{quotes.id}",
                                 "Preparing quotes: 130–170 hours per year", '<management_contexts trust="platform">')
      expect(context).not_to include("SENTINEL-POLITICS", "Omar", "Layla", "consultant_private")
      expect(client.calls.first[:system]).to include("You never design solutions")
    end
  end

  describe "what is stored" do
    it "stores opportunities, root causes and verdicts, each citing real evidence" do
      outcome, = synthesise(reply)
      expect(outcome.status).to eq(:complete)

      opportunity = ConsultancyOpportunity.sole
      expect(opportunity).to have_attributes(level: "CROSS_DEPARTMENT", opportunity_key: "op-1", status: "PROPOSED",
                                             capacity_reference: "Preparing quotes: 130–170 hours per year",
                                             strategic_finding_ids: [pricing_concern.id],
                                             affected_finding_ids: [quotes.id, price_entry.id])
      expect(opportunity.root_cause_key).to eq(RootCause.sole.root_cause_key)
      expect(RootCause.sole.fact_status).to eq("INFERRED")

      expect(ManagementValidation.find_by(strategic_finding: pricing_concern).relationship).to eq("SUPPORTED")
      contested = ManagementValidation.find_by(strategic_finding: finance_concern)
      expect(contested).to have_attributes(relationship: "POINTS_ELSEWHERE", material: true)
      expect(contested.fact_status).to eq("CONTRADICTED")

      expect(run.reload.operating_picture["how_the_business_runs"]).to include("Sales quotes")
      expect(AiRun.find_by(stage: "P11", subject: run).status).to eq("OK")
    end

    it "keeps management importance and platform priority apart" do
      synthesise(reply)
      opportunity = ConsultancyOpportunity.sole

      expect(opportunity.management_importance).to eq("HIGH")
      expect(opportunity.platform_priority).to eq("HIGH") # capacity 170 (1) + cross-department (2) + supported (1)
      expect(opportunity.platform_priority_rule_version).to eq("PRI.v1")
    end
  end

  describe "the checks" do
    it "drops a capacity figure the model altered, a design, and text naming someone" do
      bad = reply("opportunities" => [reply["opportunities"].first.merge(
        "capacity_reference" => "about 450 hours per year across all departments",
        "intervention_direction" => "Build a scheduled agent that calls the ERP API with field mapping rules.",
        "management_alignment" => "Omar raised it."
      )])
      synthesise(bad)
      opportunity = ConsultancyOpportunity.sole

      expect(opportunity.capacity_reference).to be_nil
      expect(opportunity.intervention_direction).to be_nil
      expect(opportunity.management_alignment).to be_nil
      notes = run.reload.validation_drops.map { |d| d["note"] }.join(" | ")
      expect(notes).to include("not a platform figure", "reads as a design", "names a person")
    end

    it "drops an opportunity that cites nothing real, and a root cause that explains one thing" do
      synthesise(reply("opportunities" => [reply["opportunities"].first.merge("affected_clusters" => ["cl-999"],
                                                                              "evidence" => ["wi_999999"])],
                       "root_causes" => [reply["root_causes"].first.merge("explains" => ["wi_#{quotes.id}"])]))

      expect(ConsultancyOpportunity.count).to eq(0)
      expect(RootCause.count).to eq(0)
      expect(run.reload.validation_drops.map { |d| d["note"] }.join).to include("does not exist", "fewer than two")
    end

    it "drops a problem statement that describes a person" do
      synthesise(reply("opportunities" => [reply["opportunities"].first.merge(
        "problem_statement" => "The procurement officer is slow at entering prices."
      )]))
      expect(ConsultancyOpportunity.count).to eq(0)
    end

    it "lets approvals be slow — that is work, not a person" do
      synthesise(reply("opportunities" => [reply["opportunities"].first.merge(
        "problem_statement" => "Approvals are slow, so quotations wait on sign-off."
      )]))
      expect(ConsultancyOpportunity.count).to eq(1)
    end
  end

  describe "re-runs" do
    it "leaves a consultant's approved opportunity alone and supersedes proposals the model drops" do
      synthesise(reply)
      approved = ConsultancyOpportunity.sole.revise!(status: "APPROVED")
      old_root = RootCause.sole

      run2 = SynthesisRun.create!(company: company, engagement: engagement, version: 2, trigger: "MANUAL",
                                  requested_at: Time.current, status: "RUNNING")
      described_class.call(run: run2, items: items, clusters: [],
                           client: SynthesisFakeClient.new(syntheses: [reply("root_causes" => [])]))

      expect(ConsultancyOpportunity.current.sole).to eq(approved)
      expect(old_root.reload.status).to eq("SUPERSEDED")
    end

    it "makes a new version of a proposal only when it changed" do
      synthesise(reply)
      first = ConsultancyOpportunity.sole
      run2 = SynthesisRun.create!(company: company, engagement: engagement, version: 2, trigger: "MANUAL",
                                  requested_at: Time.current, status: "RUNNING")
      described_class.call(run: run2, items: items, clusters: [], client: SynthesisFakeClient.new(syntheses: [reply]))
      expect(ConsultancyOpportunity.count).to eq(1)

      changed = reply("opportunities" => [reply["opportunities"].first.merge("confidence" => "HIGH")])
      run3 = SynthesisRun.create!(company: company, engagement: engagement, version: 3, trigger: "MANUAL",
                                  requested_at: Time.current, status: "RUNNING")
      described_class.call(run: run3, items: items, clusters: [], client: SynthesisFakeClient.new(syntheses: [changed]))
      expect(ConsultancyOpportunity.current.sole).to have_attributes(version: 2, parent_version_id: first.id,
                                                                     confidence: "HIGH")
    end
  end

  describe "when P11 can't be used" do
    it "retries once, then passes forward unsynthesised and says why" do
      outcome, client = synthesise("not json", "[]")

      expect(client.calls.size).to eq(2)
      expect(outcome).to have_attributes(status: :fallback, reason: "unusable_reply")
      expect(ConsultancyOpportunity.count).to eq(0)
      expect(AiRun.find_by(stage: "P11")).to have_attributes(status: "FALLBACK", fallback_reason: "unusable_reply")
    end

    it "does not call the model when synthesis is switched off" do
      stub_const("ENV", ENV.to_h.merge("AI_SYNTHESIS" => "false"))
      outcome, client = synthesise

      expect(client.calls).to be_empty
      expect(outcome.reason).to eq("model_off")
    end
  end

  it "runs end to end on scripted replies" do
    outcome = described_class.call(run: run, items: items, clusters: [], client: Synthesis::ScriptedClient.new)

    expect(outcome.status).to eq(:complete)
    expect(ManagementValidation.count).to eq(2)
  end
end
