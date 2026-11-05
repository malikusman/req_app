# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyPerson::Planner do
  let(:persona) { "CEO_OWNER_MD" }
  let(:limits) { { "floor" => 8, "ceiling" => 24, "stall" => 3 } }
  let(:planner) { described_class.new(snapshot: {}, persona: persona, limits: limits) }

  # A P03 capture, as the validator hands it on.
  def capture(quality: "USABLE", touched: nil, signal: "NONE", question: nil, overflow: false, statements: [],
              summary: "Something useful.", documents: [], facts: [], initiatives: [])
    target = planner.instruction&.dig("target_domain")
    touched ||= target && quality == "USABLE" ? [{ "domain" => target, "contribution" => "USABLE" }] : []
    {
      "previous_target_result" => { "domain" => target, "quality" => quality },
      "domains_touched" => touched,
      "statements" => statements,
      "planned_initiatives" => initiatives,
      "participants_mentioned" => [],
      "documents_mentioned" => documents,
      "profile_facts_discovered" => facts,
      "participant_question" => question || { "asked" => false },
      "participant_signal" => signal,
      "detail_overflow" => overflow,
      "summary_update" => summary
    }
  end

  def answer(**opts) = planner.after_answer(capture(**opts))

  def started
    planner.opening
    answer(quality: "NONE", summary: nil) # "Yes, let's start."
    planner
  end

  it "opens, then asks about an Essential area" do
    expect(planner.opening).to include("mode" => "OPENING", "state" => "OPENING")

    first = answer(quality: "NONE", summary: nil)
    expect(first).to include("mode" => "QUESTION", "state" => "BROAD_DISCOVERY", "target_domain" => "STRATEGIC_OBJECTIVES")
    expect(first["intent"]).to be_present
  end

  it "takes a CEO and a department head down different paths (Doc 08 §32)" do
    path = lambda do |who|
      p = described_class.new(snapshot: {}, persona: who, limits: limits)
      p.opening
      p.after_answer(nil)
      Array.new(5) { p.instruction["target_domain"].tap { p.after_answer(capture_for(p)) } }
    end

    expect(path.call("CEO_OWNER_MD")).not_to eq(path.call("DEPARTMENT_HEAD"))
    expect(path.call("DEPARTMENT_HEAD")).to include("BOTTLENECKS")
    expect(path.call("CEO_OWNER_MD")).to include("GROWTH_PRIORITIES")
  end

  def capture_for(p)
    target = p.instruction["target_domain"]
    { "previous_target_result" => { "quality" => "USABLE" },
      "domains_touched" => [{ "domain" => target, "contribution" => "USABLE" }], "summary_update" => "ok" }
  end

  describe "at most one follow-up per topic (Doc 08 §9.1A)" do
    it "follows up a vague answer once, then moves on and keeps the area as unknown" do
      started
      target = planner.instruction["target_domain"]

      follow_up = answer(quality: "VAGUE")
      expect(follow_up).to include("mode" => "FOLLOW_UP", "target_domain" => target)

      after = answer(quality: "VAGUE")
      expect(after["target_domain"]).not_to eq(target)
      expect(planner.coverage[target]).to include("status" => "UNKNOWN", "settled" => true)
    end

    it "asks for an example instead when they stressed it" do
      started
      target = planner.instruction["target_domain"]
      result = answer(quality: "VAGUE", statements: [{ "domain" => target, "importance_signal" => "EMPHASISED" }])
      expect(result["mode"]).to eq("EXAMPLE")
    end

    it "never probes once they have gone into operational detail" do
      started
      target = planner.instruction["target_domain"]
      result = answer(quality: "VAGUE", overflow: true)

      expect(result["target_domain"]).not_to eq(target)
      expect(planner.coverage[target]).to include("overflow" => true, "settled" => true)
    end
  end

  it "records every area one answer touches (P03 §8.1)" do
    started
    answer(touched: [{ "domain" => "STRATEGIC_OBJECTIVES", "contribution" => "USABLE" },
                     { "domain" => "BOTTLENECKS", "contribution" => "PARTIAL" },
                     { "domain" => "DECISIONS_APPROVALS", "contribution" => "USABLE" }])

    expect(planner.coverage.slice("STRATEGIC_OBJECTIVES", "BOTTLENECKS", "DECISIONS_APPROVALS")
                  .transform_values { |e| e["status"] })
      .to eq("STRATEGIC_OBJECTIVES" => "USABLE", "BOTTLENECKS" => "PARTIAL", "DECISIONS_APPROVALS" => "USABLE")
  end

  it "answers their question, then returns to the same thread" do
    started
    target = planner.instruction["target_domain"]

    aside = answer(quality: "NONE", question: { "asked" => true, "topic" => "PRICE", "text" => "What will it cost?" })
    expect(aside).to include("mode" => "HANDLE_ASIDE", "target_domain" => target, "aside_topic" => "PRICE")

    answer(quality: "VAGUE")
    expect(planner.instruction).to include("mode" => "FOLLOW_UP", "target_domain" => target)
  end

  it "pauses on request and resumes on the same thread, without restarting (Doc 08 §24)" do
    started
    target = planner.instruction["target_domain"]

    expect(answer(quality: "NONE", signal: "WANTS_PAUSE")).to include("mode" => "PAUSE", "state" => "PAUSED")

    resumed = described_class.new(snapshot: planner.snapshot, persona: persona, limits: limits).resume
    expect(resumed).to include("mode" => "RESUME", "target_domain" => target)
  end

  it "wraps up briefly when they want to stop" do
    started
    answer
    expect(answer(quality: "NONE", signal: "WANTS_END")["mode"]).to eq("PRIORITY_READ_BACK")
    expect(answer(quality: "NONE")["mode"]).to eq("SCOPE_AND_PARTICIPANTS")
    expect(answer(quality: "NONE")).to include("mode" => "CLOSING", "state" => "COMPLETE",
                                               "close_reason" => "PARTICIPANT_ENDED")
  end

  it "reflects back every few questions" do
    started
    modes = Array.new(6) { answer["mode"] }
    expect(modes).to include("REFLECT_AND_ASK")
    expect(planner.snapshot["recent_questions"]).to eq([]) # filled by record_question, not here
  end

  it "clarifies one contradiction with the profile, once" do
    started
    fact = { "field" => "locations", "value" => "Oman", "contradicts_known" => true, "evidence" => "t3" }
    result = answer(facts: [fact])
    expect(result).to include("mode" => "CLARIFY", "state" => "CLARIFICATION")
    expect(result["thread_note"]).to include("Oman")

    expect(answer(facts: [fact.merge("value" => "Qatar")])["mode"]).not_to eq("CLARIFY")
  end

  describe "ending on sufficiency, not question count (Doc 08 §22)" do
    it "closes with read-back, scope, documents, anything else, then closing" do
      started
      documents = [{ "description" => "weekly sales pack", "evidence" => "t2" },
                   { "description" => "org chart", "evidence" => "t2" },
                   { "description" => "KPI sheet", "evidence" => "t2" },
                   { "description" => "credit policy", "evidence" => "t2" }]
      answer(documents: documents)
      answer until KeyPerson::Planner::CLOSING_MODES.include?(planner.instruction["mode"])

      modes = [planner.instruction["mode"]]
      expect(planner.instruction["themes"]).to be_present
      modes << answer(quality: "NONE")["mode"] while modes.last != "CLOSING"

      expect(modes).to eq(%w[PRIORITY_READ_BACK SCOPE_AND_PARTICIPANTS DOCUMENT_REQUEST ANYTHING_ELSE CLOSING])
      expect(planner.instruction["close_reason"]).to eq("COVERAGE_COMPLETE")
      expect(planner.snapshot["participant_turns"]).to be >= limits["floor"]
      expect(KeyPerson::Coverage.sufficient?(planner.coverage, persona)).to be(true)
    end

    it "asks for at most three documents" do
      started
      answer(documents: Array.new(5) { |i| { "description" => "doc #{i}", "evidence" => "t2" } })
      answer until planner.instruction["mode"] == "DOCUMENT_REQUEST"
      expect(planner.instruction["documents"]).to eq(["doc 0", "doc 1", "doc 2"])
    end

    it "stops after answers that add nothing" do
      started
      3.times { answer(quality: "NONE", summary: nil) }
      answer(quality: "NONE") until planner.instruction["mode"] == "CLOSING"
      expect(planner.instruction["close_reason"]).to eq("STALLED")
    end

    it "stops at the ceiling as a backstop" do
      planner = described_class.new(snapshot: {}, persona: persona, limits: { "floor" => 50, "ceiling" => 5, "stall" => 99 })
      planner.opening
      5.times { planner.after_answer(capture_for_area(planner)) }
      expect(planner.closing?).to be(true)
      expect(planner.snapshot["close_reason"]).to eq("CEILING")
    end

    def capture_for_area(p)
      target = p.instruction["target_domain"]
      { "domains_touched" => target ? [{ "domain" => target, "contribution" => "PARTIAL" }] : [],
        "summary_update" => "x" }
    end
  end

  it "remembers what the assistant said, to avoid repeating it" do
    started
    planner.record_question("Where do you want the business to be in two years?")
    expect(planner.snapshot["recent_questions"]).to eq(["Where do you want the business to be in two years?"])
  end

  it "reads its limits from the company, then the environment, then the defaults" do
    company = create(:company)
    company.update!(settings: { "key_person_limits" => { "ceiling" => 30 } })
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("KEY_PERSON_FLOOR").and_return("6")
    expect(described_class.limits_for(company)).to eq("floor" => 6, "ceiling" => 30, "stall" => 3)
  end
end
