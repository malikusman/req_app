# frozen_string_literal: true

require "rails_helper"

# The hand-off to task intelligence (Doc 11 §1, §3; Doc 20 §19 "Consolidation →
# task intelligence: cluster membership, variants, normalised effort"). Pins
# the proposed contract so a change to it is a deliberate one, agreed with
# task intelligence.
RSpec.describe Synthesis::ForTaskIntelligence do
  let(:company) { create(:company, :onboarded) }
  let(:engagement) { create(:engagement, company: company) }

  before { allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false) }

  def quote_finding(hours)
    synthesis_finding(company: company, role: "Sales Coordinator", title: "Preparing quotes",
                      what_happens_now: "Check stock and the price list, fill the quotation template, email the customer",
                      hours: hours)
  end

  let!(:first) { quote_finding([100, 150]) }
  let!(:second) { quote_finding([80, 120]) }
  let!(:alone) { synthesis_finding(company: company, role: "Driver", department: "Logistics", title: "Deliveries", hours: [10, 20]) }

  before do
    context = leadership_context(engagement: engagement,
                                 consultant_private: { "political_context" => { "decision_makers" => [{ "note" => "SENTINEL-POLITICS" }] } })
    strategic_finding(context, statement: "Quotes take too long")
    run = SynthesisRun.create!(company: company, engagement: engagement, version: 1, trigger: "MANUAL", requested_at: Time.current)
    Synthesis::Run.call(run, client: Synthesis::ScriptedClient.new)
  end

  subject(:handoff) { described_class.call(engagement) }

  it "has the agreed shape" do
    expect(handoff.keys).to eq(%w[contract_version synthesis_version generated_at stale clusters unclustered_work_item_ids
                                  opportunities root_causes management_validations initiative_conflicts])
    expect(handoff["contract_version"]).to eq("SYN-TI.v1")
    expect(handoff["clusters"].first.keys).to eq(%w[key version status name cluster_type departments roles member_work_item_ids
                                                    participant_ids variants stages single_member effort sampling confidence
                                                    evidence])
    expect(handoff["opportunities"].first.keys).to include("key", "status", "level", "recommended_next_action",
                                                           "management_importance", "platform_priority",
                                                           "affected_cluster_keys", "affected_work_item_ids")
  end

  it "gives task intelligence de-duplicated effort to rank on, with the raw sum beside it" do
    cluster = handoff["clusters"].sole
    expect(cluster["member_work_item_ids"]).to contain_exactly(first.id, second.id)
    expect(cluster["effort"]).to include("raw_min" => 180.0, "dedup_min" => 180.0, "dedup_max" => 270.0)
    expect(cluster["sampling"]["recommended_participant_ids"]).to eq([first.employee_id])
    expect(handoff["unclustered_work_item_ids"]).to eq([alone.id])
  end

  it "says whose each object is, and leaves rejected ones out" do
    cluster = ProcessCluster.current.sole
    expect(handoff["clusters"].sole["status"]).to eq("PROVISIONAL")

    Synthesis::Decide.call(engagement: engagement, actor: create(:consultant_user), action: "REJECT_CLUSTER",
                           subject_id: cluster.id, rationale: "Different customers and rules")
    expect(described_class.call(engagement)["clusters"]).to be_empty
  end

  it "carries no names, nothing consultant-private and no operating-picture prose" do
    text = handoff.to_json
    expect(text).not_to include("SENTINEL-POLITICS", "Test Employee", "Layla")
    expect(text).not_to include(SynthesisRun.last.operating_picture["how_the_business_runs"])
  end
end
