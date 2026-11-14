# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyPerson::Capture do
  let(:company) { create(:company) }
  let(:engagement) { create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY") }
  let(:participant) do
    create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Layla Haddad",
                                    role_title: "CEO", persona: "CEO_OWNER_MD")
  end
  let(:session) { create(:conversation_session, participant: participant) }
  let(:planner) { KeyPerson::Planner.new(snapshot: {}, persona: "CEO_OWNER_MD").tap { |p| p.opening && p.after_answer(nil) } }
  let(:turn) { create(:conversation_turn, session: session, turn_index: 7, text: answer) }
  let(:answer) do
    "We want to grow into Saudi in the next two years, but we can't keep up with orders — everything goes " \
      "through WhatsApp and Excel and I end up approving half the quotes myself."
  end

  before { allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false) }

  def capture(reply)
    client = KeyPersonFakeClient.new(captures: reply.is_a?(Array) ? reply : [reply])
    described_class.new(session: session, turn: turn, previous_instruction: planner.instruction, planner: planner,
                        pack: KeyPerson::ContextPack.new(session), client: client).call
  end

  # P03 §8.1, abridged.
  let(:good) do
    {
      "previous_target_result" => { "domain" => "STRATEGIC_OBJECTIVES", "quality" => "USABLE" },
      "domains_touched" => [{ "domain" => "STRATEGIC_OBJECTIVES", "contribution" => "USABLE" },
                            { "domain" => "BOTTLENECKS", "contribution" => "PARTIAL" },
                            { "domain" => "MADE_UP", "contribution" => "USABLE" }],
      "statements" => [
        { "domain" => "STRATEGIC_OBJECTIVES", "statement" => "Aims to expand into Saudi Arabia within two years.",
          "original_wording" => "grow into Saudi in the next two years", "is_symptom_or_cause" => "NEITHER",
          "importance_signal" => "MENTIONED", "fact_status" => "VERIFIED", "evidence" => "t7" },
        { "domain" => "REPORTING", "statement" => "From another turn.", "evidence" => "t3" }
      ],
      "numbers_mentioned" => [{ "value" => "half", "refers_to" => "share of quotes approved", "evidence" => "t7" }],
      "profile_facts_discovered" => [{ "field" => "annual_revenue", "value" => "AED 40m", "evidence" => "t7" },
                                     { "field" => "locations", "value" => "UAE, KSA", "contradicts_known" => true }],
      "participant_signal" => "SOMETHING",
      "summary_update" => "Growth goal: Saudi within two years."
    }
  end

  it "keeps what is valid, drops what isn't, and cites this turn" do
    result = capture(good)

    expect(result["turn_id"]).to eq("t7")
    expect(result["domains_touched"].pluck("domain")).to eq(%w[STRATEGIC_OBJECTIVES BOTTLENECKS])
    expect(result["statements"].size).to eq(1)
    expect(result["statements"].first).to include("fact_status" => "REPORTED", "evidence" => "t7")
    expect(result["numbers_mentioned"].first["value"]).to eq("half")
    expect(result["profile_facts_discovered"]).to eq(
      [{ "field" => "locations", "value" => "UAE, KSA", "contradicts_known" => true, "evidence" => "t7" }]
    )
    expect(result["participant_signal"]).to eq("NONE")
    expect(AiRun.last).to have_attributes(stage: "P03", status: "OK", subject: turn)
  end

  it "moves criticism of a named person out of the statements (P03 §8.3)" do
    create(:engagement_participant, engagement: engagement, name: "Ahmed Saleh", department: "Accounts")
    reply = good.merge("statements" => [
                         { "domain" => "REPORTING", "statement" => "Ahmed never gets the monthly figures out on time.",
                           "evidence" => "t7" },
                         { "domain" => "REPORTING", "statement" => "Monthly financial figures are often delivered late.",
                           "evidence" => "t7" }
                       ], "summary_update" => "Ahmed is late with the monthly figures.")

    result = capture(reply)

    expect(result["statements"].pluck("statement")).to eq(["Monthly financial figures are often delivered late."])
    expect(result["sensitive"]).to include(include("type" => "CRITICISM_OF_PERSON"))
    expect(result["summary_update"]).to be_nil
  end

  it "parses again once, then treats the target as not filled (P03 §9)" do
    expect(capture(["not json", "still not json"])).to be_nil
    expect(AiRun.last).to have_attributes(status: "FAILED", fallback_reason: "unusable_reply")

    expect(capture(["not json", good])).to include("turn_id" => "t7")
  end

  it "returns nothing when the model errors" do
    expect(capture(Openai::Client::Error)).to be_nil
    expect(AiRun.last.fallback_reason).to eq("model_error")
  end

  it "shows P03 the previous question's target and the answer, fenced" do
    client = KeyPersonFakeClient.new(captures: [good])
    described_class.new(session: session, turn: turn, previous_instruction: planner.instruction, planner: planner,
                        pack: KeyPerson::ContextPack.new(session), client: client).call

    call = client.prompts(:capture).first
    expect(call[:system]).to start_with("You are part of Mjadi's platform")
    expect(call[:system]).to include("You are recording what a senior person")
    expect(call[:context]).to include("target: STRATEGIC_OBJECTIVES")
    expect(call[:context]).to include('<participant_answer trust="participant" turn_id="t7">')
  end
end
