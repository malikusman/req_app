# frozen_string_literal: true

require "rails_helper"

# P10 §8–§9: the model's verdict on a pair is checked before it is stored, every
# correction leans towards keeping things apart, no figure survives, and when
# the model can't be used the pair is kept separate and queued.
RSpec.describe Synthesis::RelationshipClassifier do
  let(:company) { create(:company, :onboarded) }
  let(:engagement) { create(:engagement, company: company) }
  let(:run) do
    SynthesisRun.create!(company: company, engagement: engagement, version: 1, trigger: "MANUAL",
                         requested_at: Time.current, status: "RUNNING")
  end
  let!(:quotes_a) do
    synthesis_finding(company: company, role: "Sales Coordinator", title: "Preparing quotes",
                      what_happens_now: "I check stock and the price list and email the quotation",
                      friction: "Prices live in a separate sheet")
  end
  let!(:quotes_b) do
    synthesis_finding(company: company, role: "Sales Coordinator", title: "Customer price requests",
                      what_happens_now: "I look up stock and the price list then send the quotation",
                      friction: "Checking stock by phone")
  end
  let(:pairs) { Synthesis::Candidates.call(Synthesis::WorkItems.call(company)) }

  before { allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false) }

  def reply(**overrides)
    {
      "relationship" => "SAME_PROCESS", "confidence" => "MEDIUM", "recommendation" => "PROVISIONAL_CLUSTER",
      "evidence_for" => ["Same business object: customer quotation"], "evidence_against" => [],
      "tests" => { "same_purpose" => "YES", "same_business_object" => "YES" },
      "variant_assessment" => { "material_differences" => [], "would_one_deep_dive_represent_both" => "YES",
                                "distinguishing_factors" => ["NONE"] },
      "recommendation_note" => nil, "clarification_needed" => nil,
      "effort_overlap" => { "same_execution" => "NO", "note" => "Each prepares quotes for their own customers." },
      "rationale" => "Both prepare customer quotations from stock and price lookups."
    }.merge(overrides)
  end

  def classify(*replies)
    client = SynthesisFakeClient.new(relationships: replies)
    [described_class.call(run: run, pairs: pairs, client: client), client]
  end

  it "stores a checked verdict, logs the run, and sends no names or leadership content" do
    relationships, client = classify(reply)

    relationship = relationships.first
    expect(relationship).to have_attributes(relationship_type: "SAME_PROCESS", confidence: "MEDIUM",
                                            recommendation: "PROVISIONAL_CLUSTER", same_execution: "NO",
                                            origin: "AI", prompt_version: "P10.v1")
    expect(relationship.from_finding_id).to eq(quotes_a.id)
    expect(AiRun.where(stage: "P10", status: "OK", subject: run).count).to eq(1)

    context = client.contexts(:relationship).first
    expect(client.calls.first[:system]).to include("You are part of Mjadi's platform", "A wrong merge is worse")
    expect(context).to include('<evidence_a trust="participant">', "Prices live in a separate sheet", "<shared_signals")
    expect(context).not_to include(quotes_a.employee.display_name)
  end

  it "makes an auto-cluster at MEDIUM provisional, and records why" do
    classifier = described_class.new(run, pairs, SynthesisFakeClient.new(relationships: [reply("recommendation" => "AUTO_CLUSTER")]), {})
    relationship = classifier.call.first

    expect(relationship.recommendation).to eq("PROVISIONAL_CLUSTER")
    expect(classifier.drops.map { |d| d["note"] }.join).to include("AUTO_CLUSTER needs HIGH")
  end

  it "keeps a LOW-confidence verdict apart, and never clusters an independent pair" do
    expect(classify(reply("confidence" => "LOW")).first.first.recommendation).to eq("KEEP_SEPARATE")
    ProcessRelationship.delete_all
    expect(classify(reply("relationship" => "DEPENDENCY")).first.first.recommendation).to eq("KEEP_SEPARATE")
  end

  it "drops any text carrying a figure, so no number from P10 is ever stored" do
    relationship = classify(reply("effort_overlap" => { "same_execution" => "UNKNOWN",
                                                        "note" => "Combined 12 hours a week after removing 4" },
                                  "rationale" => "About 3 quotes a day each.")).first.first

    expect(relationship.effort_note).to be_nil
    expect(relationship.rationale).to be_nil
    expect(relationship.attributes.values.grep(String).join).not_to match(/\d+ hours/)
  end

  it "turns a CLARIFY with no question into a consultant review" do
    expect(classify(reply("recommendation" => "CLARIFY")).first.first.recommendation).to eq("CONSULTANT_REVIEW")
  end

  it "retries an unusable reply once, then keeps the pair separate and queues it" do
    relationships, client = classify("not json", reply("relationship" => "MERGED_PROBABLY"))

    expect(client.calls.size).to eq(2)
    expect(relationships.first).to have_attributes(relationship_type: "INDEPENDENT", recommendation: "KEEP_SEPARATE",
                                                   origin: "FALLBACK")
    expect(relationships.first).to be_needs_review
    expect(AiRun.find_by(stage: "P10", subject: run)).to have_attributes(status: "FALLBACK",
                                                                         fallback_reason: "unusable_reply")
  end

  it "rejects a verdict that gives no evidence for itself" do
    relationships, = classify(reply("evidence_for" => []), reply("evidence_for" => []))
    expect(relationships.first.origin).to eq("FALLBACK")
  end

  it "keeps every pair separate when synthesis is switched off" do
    stub_const("ENV", ENV.to_h.merge("AI_SYNTHESIS" => "false"))
    relationships, client = classify

    expect(client.calls).to be_empty
    expect(relationships.first).to have_attributes(origin: "FALLBACK", relationship_type: "INDEPENDENT")
    expect(AiRun.find_by(stage: "P10")).to have_attributes(fallback_reason: "model_off")
  end

  it "supersedes the earlier verdict on the same two findings" do
    first = classify(reply).first.first
    second = classify(reply("relationship" => "VARIANT")).first.first

    expect(first.reload.status).to eq("SUPERSEDED")
    expect(second).to have_attributes(version: 2, parent_version_id: first.id, status: "CURRENT")
  end

  it "runs the whole step on scripted replies" do
    relationship = described_class.call(run: run, pairs: pairs, client: Synthesis::ScriptedClient.new).first

    expect(relationship).to have_attributes(relationship_type: "SAME_PROCESS", origin: "AI")
  end
end
