# frozen_string_literal: true

# Local LM Studio companion eval harness.
#
#   LIVE=1 WRITE=1 bundle exec rails scenario:companion
#
# Expects OPENAI_BASE_URL pointing at LM Studio (or OpenAI) with ALLOW_MOCKS=0.
# Companion turns hit the live model; addendum/promote discovery turns are stubbed
# after reopen is asserted (isolates companion quality from LangGraph flakiness).

require "json"
require "fileutils"

class CompanionScenarioRunner
  SLUG = "companion-eval-pilot"
  ARTIFACT_DIR = begin
    shared = Pathname.new("/docs/manual-test/companion-eval")
    shared.exist? || shared.dirname.exist? ? shared : Rails.root.join("tmp", "companion-eval")
  end
  JUDGE_MIN = 0.6
  JUDGE_PASS_RATE = 0.70

  Scenario = Struct.new(
    :id, :label, :message, :channel, :expect_status, :expect_agent, :expect_promote,
    :expect_tools_label, :judge, :before, keyword_init: true
  )

  def self.call(live: ENV["LIVE"] == "1", write: ENV["WRITE"] == "1")
    new(live: live, write: write).call
  end

  def initialize(live:, write:)
    @live = live
    @write = write
    @results = []
    @checks = []
  end

  def call
    $stdout.sync = true
    assert_live_ready!
    provision!
    run_scenarios!
    summary = summarize!
    write_artifacts!(summary) if @write
    print_summary(summary)
    raise "Companion scenario eval failed — see RESULTS.json / console" unless summary[:ok]

    summary
  end

  private

  def assert_live_ready!
    client = Openai::Client.new
    unless client.configured?
      raise "OpenAI/LM Studio not configured. Set OPENAI_BASE_URL + OPENAI_API_KEY (PROFILE B)."
    end
    if MocksAllowed.allowed? && ENV["ALLOW_MOCKS"].to_s != "0" && !@live
      raise "Refusing mock mode. Run with ALLOW_MOCKS=0 LIVE=1 against LM Studio."
    end
    if MocksAllowed.allowed? && ENV["ALLOW_MOCKS"].to_s != "0"
      warn "[companion-eval] WARN: ALLOW_MOCKS is on — replies may be mocks. Prefer ALLOW_MOCKS=0."
    end
  end

  def provision!
    @company = Company.find_or_initialize_by(slug: SLUG)
    @company.assign_attributes(
      name: "Companion Eval Pilot",
      display_name: "Companion Eval Pilot",
      approval_status: "approved",
      approved_at: Time.current,
      locale: "en",
      company_profile: { "industry" => "logistics", "region" => "UAE" }
    )
    @company.save!

    @employee = Employee.find_or_initialize_by(company: @company, phone_e164: "+971500000099")
    @employee.assign_attributes(
      display_name: "Aisha Eval",
      department: "Finance",
      role_title: "Accounts Payable Specialist",
      seniority: "individual_contributor",
      onboarding_step: "verified",
      participation_status: "completed",
      preferred_language: "en",
      completed_at: Time.current
    )
    @employee.save!

    ensure_playbook!
    ensure_catalog!
    reset_conversation!(seed_history: true)
  end

  def ensure_playbook!
    %w[default Finance finance].each do |dept|
      pb = DiscoveryPlaybook.find_or_initialize_by(department: dept, version: 1)
      next if pb.persisted? && pb.active?

      platform = PlatformUser.first || PlatformUser.create!(
        email: "companion-eval@reqapp.local",
        password: "Password1!",
        name: "Companion Eval",
        role: "support"
      )
      pb.assign_attributes(
        prompt_block: "Ask about AP workflows, tools, and friction.",
        active: true,
        activated_at: Time.current,
        created_by_platform_user: platform
      )
      pb.save!
    end
  end

  def ensure_catalog!
    entry = SolutionCatalogEntry.find_or_initialize_by(slug: "worktruth-ap-copilot-eval")
    entry.assign_attributes(
      name: "Worktruth AP Copilot",
      vendor: "Worktruth",
      category: "ai_agent",
      description: "AP invoice matching and exception triage for freight finance teams.",
      tags: %w[Finance AP invoice matching],
      match_keywords: %w[invoice matching AP freight POD],
      active: true,
      partnership_tier: "preferred",
      entity_type: "tool",
      published_at: Time.current
    )
    entry.save!

    CompanyCatalogMatch.find_or_create_by!(
      company_id: @company.id,
      solution_catalog_entry_id: entry.id
    ) do |m|
      m.score = 0.92
      m.matched_at = Time.current
      m.why_it_fits = "Fits freight AP invoice matching at Companion Eval Pilot"
    end

    Recommendation.find_or_create_by!(company: @company, title: "Automate POD exception capture") do |r|
      r.description = "Reduce Excel retyping of handwritten POD notes before SAP posting."
      r.priority = "high"
      r.status = "published"
      r.company_feedback = "no_response"
    end
  end

  def reset_conversation!(seed_history:)
    @conversation = @employee.conversations.order(created_at: :desc).first
    @conversation ||= Conversation.create!(
      employee: @employee,
      company: @company,
      status: "completed",
      question_count: 10,
      started_at: 2.days.ago,
      completed_at: 1.day.ago,
      last_activity_at: Time.current,
      state_snapshot: { "question_target" => 10 }
    )

    @conversation.update!(
      status: "completed",
      question_count: 10,
      completed_at: Time.current,
      last_activity_at: Time.current,
      state_snapshot: {
        "question_target" => 10,
        "companion" => { "notes" => [], "awaiting_promote_confirm" => false }
      }
    )

    return unless seed_history

    if @conversation.messages.none?
      Message.create!(
        conversation: @conversation,
        direction: "outbound",
        channel: "whatsapp",
        message_type: "text",
        body: "Walk me through how freight invoices get approved.",
        is_discovery_question: true
      )
      Message.create!(
        conversation: @conversation,
        direction: "inbound",
        channel: "whatsapp",
        message_type: "text",
        body: "We match PODs in Excel then chase dual approval before SAP FB60."
      )
    end

    if @conversation.conversation_insights.none?
      ConversationInsight.create!(
        conversation: @conversation,
        employee: @employee,
        company: @company,
        turn_number: 1,
        insight_type: "turn_summary",
        summary: "AP clerk retypes POD exceptions into Excel; dual approval bottlenecks before SAP."
      )
    end
  end

  def scenarios
    [
      Scenario.new(
        id: "C1",
        label: "casual",
        message: "thanks!",
        channel: "whatsapp",
        expect_status: "completed",
        expect_agent: "companion",
        judge: true
      ),
      Scenario.new(
        id: "C2",
        label: "ask",
        message: "how do I chase overdue approvals faster?",
        channel: "whatsapp",
        expect_status: "completed",
        expect_agent: "companion",
        judge: true
      ),
      Scenario.new(
        id: "C3",
        label: "tools",
        message: "any tools for invoice matching?",
        channel: "whatsapp",
        expect_status: "completed",
        expect_agent: "companion",
        expect_tools_label: true,
        judge: true
      ),
      Scenario.new(
        id: "C7",
        label: "refuse-interview-feel",
        message: "cool, I'll check those later",
        channel: "whatsapp",
        expect_status: "completed",
        expect_agent: "companion",
        judge: true
      ),
      Scenario.new(
        id: "C4",
        label: "share",
        message: "Today I spent 2 hours retyping handwritten POD notes into Excel before dual approval",
        channel: "whatsapp",
        expect_status: "completed",
        expect_agent: "companion",
        expect_promote: true,
        judge: true
      ),
      Scenario.new(
        id: "C5",
        label: "promote",
        message: "yes",
        channel: "whatsapp",
        expect_status: "discovery",
        expect_agent: nil,
        judge: false,
        before: -> { stub_discovery_turn! }
      ),
      Scenario.new(
        id: "C6",
        label: "addendum",
        message: "add this to my interview: dual CFO approval takes 5 days on average",
        channel: "whatsapp",
        expect_status: "discovery",
        expect_agent: nil,
        judge: false,
        before: -> {
          complete_again!
          stub_discovery_turn!
        }
      ),
      Scenario.new(
        id: "W1",
        label: "web-casual",
        message: "thanks!",
        channel: "web",
        expect_status: "completed",
        expect_agent: "companion",
        judge: true,
        before: -> { complete_again! }
      )
    ]
  end

  def run_scenarios!
    scenarios.each do |scenario|
      scenario.before&.call
      q_before = @conversation.reload.question_count.to_i
      run_one!(scenario, q_before)
    end
  ensure
    unstub_discovery_turn!
  end

  def run_one!(scenario, q_before)
    puts "→ #{scenario.id} #{scenario.label}: #{scenario.message.truncate(80)}"

    if scenario.channel == "web"
      Web::TurnRouter.handle_text(
        employee: @employee,
        conversation: @conversation,
        text: scenario.message
      )
    else
      Whatsapp::DiscoveryHandler.new(
        employee: @employee,
        conversation: @conversation,
        client: Whatsapp::MetaClient.new,
        channel: "whatsapp"
      ).handle_inbound_text(scenario.message)
    end

    @conversation = @employee.conversations.where.not(status: "abandoned").order(updated_at: :desc).first
    outbound = @conversation.messages.where(direction: "outbound").order(:created_at).last
    reply = outbound&.body.to_s
    agent_id = outbound&.agent_id
    layer_a = layer_a_score(scenario, reply, agent_id, q_before)
    layer_b = scenario.judge ? layer_b_judge(scenario, reply) : { "skipped" => true }

    row = {
      id: scenario.id,
      label: scenario.label,
      message: scenario.message,
      channel: scenario.channel,
      status: @conversation.status,
      agent_id: agent_id,
      is_discovery_question: outbound&.is_discovery_question,
      awaiting_promote: Companion::NoteStore.awaiting_promote_confirm?(@conversation),
      question_count_before: q_before,
      question_count_after: @conversation.question_count,
      reply: reply,
      layer_a: layer_a,
      layer_b: layer_b,
      pass: layer_a[:pass] && (layer_b["skipped"] || layer_b_pass?(layer_b))
    }
    @results << row
    @checks << row[:pass]
    puts "  status=#{row[:status]} agent=#{agent_id} pass=#{row[:pass]} a=#{layer_a[:score]} b=#{layer_b['score'] || 'n/a'}"
    puts "  reply: #{reply.truncate(160)}"
  rescue StandardError => e
    @results << {
      id: scenario.id,
      label: scenario.label,
      message: scenario.message,
      error: "#{e.class}: #{e.message}",
      pass: false
    }
    @checks << false
    warn "  FAIL #{e.class}: #{e.message}"
  end

  def layer_a_score(scenario, reply, agent_id, q_before)
    checks = {}
    checks[:status] = @conversation.status == scenario.expect_status
    if scenario.expect_agent
      checks[:agent] = agent_id.to_s == scenario.expect_agent
    end
    checks[:reply_present] = reply.present?
    if scenario.expect_status == "completed"
      checks[:not_discovery_question] = outbound_not_discovery_question?
      checks[:question_count_stable] = @conversation.question_count.to_i == q_before
      checks[:length_ok] = reply.length.between?(10, 2000)
      checks[:no_interview_leak] = !interview_leak?(reply)
      checks[:no_hallucinated_stack] = !reply.match?(/\b(Kafka|Elasticsearch|Tableau)\b/i)
    end
    if scenario.expect_promote
      checks[:awaiting_promote] = Companion::NoteStore.awaiting_promote_confirm?(@conversation)
      checks[:promote_prompt] = reply.match?(/report|interview/i)
    end
    if scenario.expect_tools_label
      checks[:tools_formatting] =
        reply.match?(/company catalog/i) ||
        reply.match?(/Not from your company catalog/i) ||
        reply.match?(/don't have a strong company-catalog match/i)
      if reply.match?(/Not from your company catalog/i)
        checks[:general_labeled] = true
      end
    end

    passed = checks.values.all?
    score = checks.empty? ? 0.0 : checks.values.count(true).to_f / checks.size
    { pass: passed, score: score.round(3), checks: checks }
  end

  def outbound_not_discovery_question?
    msg = @conversation.messages.where(direction: "outbound").order(:created_at).last
    msg.nil? || msg.is_discovery_question != true
  end

  def interview_leak?(reply)
    return true if reply.match?(/\b(Q\s*1|question 1 of|first question)\b/i)
    return true if reply.scan(/\?\s*$/).any? && reply.scan(/\n\s*\d+[\.\)]/).size >= 3

    false
  end

  def layer_b_judge(scenario, reply)
    return { "skipped" => true, "reason" => "empty_reply" } if reply.blank?

    client = Openai::Client.new
    result = client.companion_eval_judge(
      user_message: scenario.message,
      assistant_reply: reply,
      intent_hint: scenario.label
    )
    result.merge("pass" => layer_b_pass?(result))
  rescue StandardError => e
    { "error" => "#{e.class}: #{e.message}", "score" => 0.0, "pass" => false, "interview_leak" => true }
  end

  def layer_b_pass?(layer_b)
    return true if layer_b["skipped"]
    return false if layer_b["interview_leak"] == true

    layer_b["score"].to_f >= JUDGE_MIN
  end

  def stub_discovery_turn!
    Thread.current[:companion_eval_stub_discovery] = true
    CompanionEvalDiscoveryStub.install!
  end

  def unstub_discovery_turn!
    Thread.current[:companion_eval_stub_discovery] = false
  end

  def complete_again!
    Thread.current[:companion_eval_stub_discovery] = false
    @conversation.reload
    @conversation.update!(
      status: "completed",
      completed_at: Time.current,
      last_activity_at: Time.current,
      state_snapshot: @conversation.state_snapshot.merge(
        "companion" => {
          "notes" => Array(Companion::NoteStore.companion_state(@conversation)["notes"]),
          "awaiting_promote_confirm" => false
        }
      )
    )
  end

  def summarize!
    judged = @results.select { |r| r.dig(:layer_b).is_a?(Hash) && !r.dig(:layer_b, "skipped") && !r[:error] }
    judge_passes = judged.count { |r| layer_b_pass?(r[:layer_b]) }
    judge_rate = judged.empty? ? 1.0 : judge_passes.to_f / judged.size
    structural_ok = @results.all? { |r| r[:pass] && r[:error].nil? }
    ok = structural_ok && judge_rate >= JUDGE_PASS_RATE

    {
      ok: ok,
      structural_ok: structural_ok,
      judge_pass_rate: judge_rate.round(3),
      judge_min: JUDGE_MIN,
      model: ENV.fetch("OPENAI_MODEL", "unknown"),
      base_url: ENV["OPENAI_BASE_URL"].to_s.presence || "default",
      allow_mocks: MocksAllowed.allowed?,
      results: @results,
      at: Time.current.iso8601
    }
  end

  def write_artifacts!(summary)
    dir = ARTIFACT_DIR.expand_path
    FileUtils.mkdir_p(dir)
    File.write(dir.join("RESULTS.json"), JSON.pretty_generate(summary))

    lines = []
    lines << "# Companion local eval observations"
    lines << ""
    lines << "- **When:** #{summary[:at]}"
    lines << "- **Model:** `#{summary[:model]}`"
    lines << "- **Base URL:** `#{summary[:base_url]}`"
    lines << "- **ALLOW_MOCKS:** #{summary[:allow_mocks]}"
    lines << "- **Structural OK:** #{summary[:structural_ok]}"
    lines << "- **Judge pass rate:** #{summary[:judge_pass_rate]} (threshold #{JUDGE_PASS_RATE})"
    lines << "- **Overall:** #{summary[:ok] ? 'PASS' : 'FAIL'}"
    lines << ""
    lines << "| ID | Label | Status | Agent | A score | B score | Pass |"
    lines << "|----|-------|--------|-------|---------|---------|------|"
    summary[:results].each do |r|
      b = if r[:error]
            "err"
          elsif r.dig(:layer_b, "skipped")
            "skip"
          else
            r.dig(:layer_b, "score") || "-"
          end
      a = r.dig(:layer_a, :score) || r.dig(:layer_a, "score") || "-"
      lines << "| #{r[:id]} | #{r[:label]} | #{r[:status] || 'err'} | #{r[:agent_id] || '-'} | #{a} | #{b} | #{r[:pass]} |"
    end
    lines << ""
    lines << "## Sample replies"
    summary[:results].each do |r|
      next if r[:reply].blank?

      lines << ""
      lines << "### #{r[:id]} — #{r[:label]}"
      lines << ""
      lines << "**User:** #{r[:message]}"
      lines << ""
      lines << "**Assistant:**"
      lines << ""
      lines << "> #{r[:reply].to_s.gsub("\n", "\n> ")}"
      if r.dig(:layer_b, "notes").present?
        lines << ""
        lines << "_Judge:_ #{r.dig(:layer_b, 'notes')}"
      end
    end
    lines << ""
    lines << "## How to re-run"
    lines << ""
    lines << "```bash"
    lines << "# LM Studio on :1234 with gemma loaded, then:"
    lines << "docker compose exec -e OPENAI_BASE_URL=http://host.docker.internal:1234/v1 \\"
    lines << "  -e OPENAI_API_KEY=lm-studio \\"
    lines << "  -e OPENAI_MODEL=google/gemma-4-12b-qat \\"
    lines << "  -e DOCS_MODEL_FAST=google/gemma-4-12b-qat \\"
    lines << "  -e OPENAI_JSON_MODE=false \\"
    lines << "  -e OPENAI_MAX_TOKENS=2500 \\"
    lines << "  -e ALLOW_MOCKS=0 \\"
    lines << "  -e LIVE=1 -e WRITE=1 \\"
    lines << "  rails bundle exec rails scenario:companion"
    lines << "```"
    File.write(dir.join("OBSERVATIONS.md"), lines.join("\n"))
    puts "Wrote #{dir.join('RESULTS.json')} and OBSERVATIONS.md"
  end

  def print_summary(summary)
    puts ""
    puts "=== Companion eval ==="
    puts "structural_ok=#{summary[:structural_ok]} judge_rate=#{summary[:judge_pass_rate]} overall=#{summary[:ok] ? 'PASS' : 'FAIL'}"
  end
end

# Isolates companion eval from LangGraph discovery flakiness (C5/C6).
module CompanionEvalDiscoveryStub
  module ClassMethods
    def call(conversation:, employee:, user_message:, inbound_message: nil, defer_on_failure: true)
      if Thread.current[:companion_eval_stub_discovery]
        {
          "assistant_message" => "Thanks — I've captured that addendum for discovery.",
          "completed" => false,
          "question_count" => conversation.question_count.to_i + 1,
          "insight" => { "summary" => user_message.to_s.truncate(200) },
          "routing_decision" => { "action" => "continue", "agent" => "domain_finance" }
        }
      else
        super
      end
    end
  end

  def self.install!
    return if @installed

    Discovery::ProcessTurnService.singleton_class.prepend(ClassMethods)
    @installed = true
  end
end
