# frozen_string_literal: true

# The key-person benchmark (Doc 08 §31–32, P02–P04 evaluation tables): each
# scenario in spec/fixtures/key_person/scenarios is played through the real
# conversation — planner, prompts, guard, validation — against the configured
# model, and the result is checked for the critical failures the prompts name:
# a solution or price brought up, a known fact asked again, more than one
# follow-up on a topic, a repeated question, a name in a finding, and whatever
# the scenario expects (an initiative captured, a question handled, Arabic).
#
#   rails key_person:eval                # every scenario, the configured model
#   rails key_person:eval ONLY=ceo_trading
#   rails key_person:eval SCRIPTED=1     # a smoke run of the harness itself
#
# Everything a run writes is rolled back. It reports; it doesn't fail a build:
# release decisions are made on the production model (Doc 05 §3.2).
class KeyPersonEval
  SCENARIOS = Rails.root.join("spec/fixtures/key_person/scenarios")
  BY_MODE = {
    "en" => { "OPENING" => "Yes, let's start.", "PRIORITY_READ_BACK" => "The first of those matters most.",
              "SCOPE_AND_PARTICIPANTS" => "Sales and procurement; the coordinators know the day-to-day.",
              "DOCUMENT_REQUEST" => "I'll share what I can later.", "ANYTHING_ELSE" => "No, that's everything." },
    "ar" => { "OPENING" => "نعم، لنبدأ.", "PRIORITY_READ_BACK" => "الأول هو الأهم.",
              "SCOPE_AND_PARTICIPANTS" => "المبيعات والمشتريات، والمنسقون يعرفون العمل اليومي.",
              "DOCUMENT_REQUEST" => "سأشارك ما أستطيع لاحقاً.", "ANYTHING_ELSE" => "لا، هذا كل شيء." }
  }.freeze
  FILLER = { "en" => "Nothing more to add on that.", "ar" => "لا شيء أضيفه على ذلك." }.freeze
  # The assistant offering something, rather than asking (P02 rule 7).
  OFFER = /\b(would|could|should|might|can)\b[^?.]*\b(ai|automation|automate|agent|tool|software|chatbot)\b[^?.]*\b(help|solve|fix|handle)\b/i

  def self.call(only: ENV["ONLY"], scripted: ENV["SCRIPTED"].present?)
    new(only: only, scripted: scripted).call
  end

  def initialize(only:, scripted:)
    @only = only.to_s.split(",").map(&:strip).reject(&:blank?)
    @scripted = scripted
  end

  def call
    client = @scripted ? KeyPerson::ScriptedClient.new : Openai::Client.new
    abort "No model configured: set OPENAI_API_KEY, or SCRIPTED=1 to smoke-test the harness" unless client.configured?

    files = Dir[SCENARIOS.join("*.yml")].sort.select { |f| @only.empty? || @only.include?(File.basename(f, ".yml")) }
    results = files.map { |file| run(file, client) }
    report(results)
  end

  private

  def run(file, client)
    spec = YAML.load_file(file)
    result = nil
    ActiveRecord::Base.transaction do
      session = set_up(spec)
      play(spec, session, client)
      KeyPerson::ContextBuilder.call(session.reload, client: client)
      result = evaluate(File.basename(file, ".yml"), spec, session.reload)
      raise ActiveRecord::Rollback
    end
    result
  end

  def set_up(spec)
    company = Company.create!(name: "Eval #{SecureRandom.hex(3)}", slug: "eval-#{SecureRandom.hex(4)}", approval_status: "approved",
                              company_profile: { "industry" => "Wholesale distribution", "country" => "United Arab Emirates",
                                                 "org_departments" => %w[Sales Procurement Finance] })
    engagement = company.engagements.create!(status: "KEY_PERSON_DISCOVERY", scope_type: "COMPANY", languages: ["en"],
                                             planned_departments: [{ "name" => "Sales", "count" => 2 }])
    engagement.participants.create!(company: company, participant_type: "EMPLOYEE", name: "Ahmed Saleh", department: "Finance")
    participant = engagement.participants.create!(
      company: company, participant_type: "KEY_PERSON", source: "KEY_USER", name: "Eval Participant",
      role_title: spec["role_title"], persona: spec["persona"], scope: spec["scope"],
      preferred_language: spec["language"] || "en", participation_status: "INVITED"
    )
    KeyPerson::Conversation.new(participant).start!
  end

  def play(spec, session, client)
    lang = spec["language"] || "en"
    used = Set.new
    answered = 0
    60.times do
      session.reload
      break if session.finished?

      last = session.turns.from_assistant.last
      answered += 1
      text = spec.dig("inject", answered) ||
             (last.targeted_slot && !used.include?(last.targeted_slot) && spec.dig("answers", last.targeted_slot)&.tap { used << last.targeted_slot }) ||
             BY_MODE[lang][last.mode] || FILLER[lang]
      KeyPerson::Turn.new(session, client: client).answer!(text: text)
    end
  end

  def evaluate(name, spec, session)
    turns = session.turns.to_a
    assistant = turns.select(&:assistant?)
    pack = KeyPerson::ContextPack.new(session)
    context = session.management_discovery_context
    runs = AiRun.where(subject: [session, *turns])
    checks = {}

    said_so_far = ""
    offending = []
    turns.each do |turn|
      if turn.participant?
        said_so_far += " #{turn.text}"
        next
      end
      offending << turn.locator if KeyPerson::Guard.blocked_term(turn.text, turn.mode, said_so_far) || turn.text.match?(OFFER)
    end
    checks["no solution, price or process talk"] = offending.empty? ? :pass : "critical: #{offending.join(', ')}"

    known = assistant.select { |t| KeyPerson::Guard.asks_known_fact(t.text, pack.known_fields) }.map(&:locator)
    checks["never asks a known fact"] = known.empty? ? :pass : "critical: #{known.join(', ')}"

    follow_ups = assistant.select { |t| %w[FOLLOW_UP EXAMPLE].include?(t.mode) }.group_by(&:targeted_slot)
                          .select { |_, list| list.size > 1 }.keys
    checks["at most one follow-up per topic"] = follow_ups.empty? ? :pass : "critical: #{follow_ups.join(', ')}"

    questions = assistant.select { |t| %w[QUESTION REFLECT_AND_ASK FOLLOW_UP EXAMPLE].include?(t.mode) }
    repeats = questions.each_with_index.select { |t, i| KeyPerson::Guard.repeats?(t.text, questions.first(i).map(&:text)) }.map { |t, _| t.locator }
    checks["no repeated question"] = repeats.empty? ? :pass : "fail: #{repeats.join(', ')}"

    names = Array(context&.strategic_findings).select { |f| pack.known_names.any? { |n| f.statement.include?(n) } }
    checks["no name in a finding"] = names.empty? ? :pass : "critical: #{names.size}"

    if (initiative = spec.dig("expect", "initiative"))
      found = context&.planned_initiatives&.pluck(:initiative_type).to_a
      checks["#{initiative} captured"] = found.include?(initiative) ? :pass : "fail: got #{found.inspect}"
    end
    if spec.dig("expect", "aside")
      checks["question handled"] = assistant.any? { |t| t.mode == "HANDLE_ASIDE" } ? :pass : "fail"
    end
    if (type = spec.dig("expect", "sensitive"))
      sensitive = turns.flat_map { |t| Array(t.capture&.dig("sensitive")) }.pluck("type")
      checks["#{type.downcase.tr('_', ' ')} kept aside"] = sensitive.include?(type) ? :pass : "fail"
    end
    if spec.dig("expect", "language") == "ar"
      arabic = assistant.count { |t| t.text.match?(/\p{Arabic}/) }
      checks["replies in Arabic"] = arabic >= (assistant.size * 0.8) ? :pass : "fail: #{arabic}/#{assistant.size}"
    end

    {
      name: name, title: spec["title"], close_reason: session.close_reason,
      answers: turns.count(&:participant?), coverage: session.state_snapshot["coverage"].count { |_, e| e["status"] == "USABLE" },
      context: context&.status, findings: Array(context&.strategic_findings).size,
      p02_fallbacks: runs.where(stage: "P02", status: "FALLBACK").count, p02_retries: runs.where(stage: "P02", status: "RETRIED").count,
      p03_failures: runs.where(stage: "P03", status: "FAILED").count, checks: checks
    }
  end

  def report(results)
    critical = 0
    results.each do |r|
      puts ""
      puts "#{r[:title]} (#{r[:name]})"
      puts "  closed: #{r[:close_reason]} after #{r[:answers]} answers; #{r[:coverage]}/16 areas usable; " \
           "context #{r[:context]}, #{r[:findings]} findings"
      puts "  P02 fallbacks #{r[:p02_fallbacks]}, retries #{r[:p02_retries]}; P03 failures #{r[:p03_failures]}"
      r[:checks].each do |check, outcome|
        critical += 1 if outcome.to_s.start_with?("critical")
        puts format("  %-36s %s", check, outcome == :pass ? "pass" : outcome)
      end
    end
    puts ""
    puts "#{results.size} scenario(s), #{critical} critical failure(s)#{@scripted ? ' — scripted replies, not a model result' : ''}"
  end
end
