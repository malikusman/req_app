# frozen_string_literal: true

# The consolidation and synthesis benchmark (Doc 20 §16, P10 §10, P11 §11).
#
# spec/fixtures/synthesis/pairs.yml — two pieces of work each; checks how P10
# relates them (after the platform's own shortlisting) and whether they end up
# grouped. Critical failures: merging on name alone, any figure in the reply,
# clustering at LOW confidence, a handoff called duplication.
#
# spec/fixtures/synthesis/syntheses.yml — a small engagement each; runs the
# whole pass and checks P11's root causes, opportunities, leadership verdicts,
# initiative handling and coverage notes. Critical failures: an invented or
# altered figure, a design, a person named or described, a company-wide claim
# from one department.
#
# Everything runs in a transaction that is rolled back. Without REAL=1 (or
# with SCRIPTED=1) the model is scripted — which checks the plumbing, not the
# model; release decisions need the production model (Doc 05 §3.2).
#
#   rails synthesis:eval                       # scripted
#   rails synthesis:eval REAL=1 ONLY=two_weekly_reports,management_blames_finance
class SynthesisEval
  DIR = Rails.root.join("spec/fixtures/synthesis")
  # P10 §10's critical failures. Other corrections — an auto-cluster made
  # provisional — are reported but are not critical.
  CRITICAL_P10 = /carrying a figure|nothing clusters at LOW/
  CRITICAL_P11 = /never computed|reads as a design|names a person|describes a person|not a platform figure/

  def self.call(only: ENV["ONLY"], real: ENV["REAL"].present? && ENV["SCRIPTED"].blank?)
    new(only: only.to_s.split(",").map(&:strip).reject(&:empty?), real: real).call
  end

  def initialize(only:, real:)
    @only = only
    @real = real
  end

  def call
    pairs = load("pairs.yml")
    syntheses = load("syntheses.yml")
    puts "Consolidation and synthesis benchmark — #{@real ? 'the real model' : 'scripted'}, " \
         "#{pairs.size} pairs, #{syntheses.size} engagements"
    results = pairs.map { |s| run(s) { |run, company| check_pair(s, run, company) } } +
              syntheses.map { |s| run(s) { |run, company| check_synthesis(s, run, company) } }
    passed = results.count { |r| r[:failures].empty? }
    critical = results.sum { |r| r[:critical] }
    puts ""
    puts "#{passed}/#{results.size} passed, #{critical} critical failure#{'s' unless critical == 1}"
    results
  end

  private

  def load(file)
    list = YAML.safe_load_file(DIR.join(file))
    @only.any? ? list.select { |s| @only.include?(s["name"]) } : list
  end

  def run(scenario)
    result = nil
    ActiveRecord::Base.transaction do
      company, engagement = build(scenario)
      run = SynthesisRun.create!(company: company, engagement: engagement, version: 1, trigger: "MANUAL",
                                 requested_at: Time.current)
      result = yield(run, company)
      raise ActiveRecord::Rollback
    end
    failures, critical = result
    status = if failures.empty? then "pass"
             else "#{critical.positive? ? 'CRITICAL' : 'FAIL'} — #{failures.join('; ')}"
             end
    puts format("  %-30s %s", scenario["name"], status)
    { name: scenario["name"], failures: failures, critical: critical }
  rescue StandardError => e
    puts format("  %-30s ERROR — %s: %s", scenario["name"], e.class, e.message)
    { name: scenario["name"], failures: [e.message], critical: 0 }
  end

  def build(scenario)
    company = Company.create!(name: "Benchmark #{scenario['name']}", slug: "synthesis-eval-#{SecureRandom.hex(4)}",
                              company_profile: { "industry" => "wholesale_distribution",
                                                 "org_departments" => scenario["departments"] || [] },
                              settings: Company::DEFAULT_SETTINGS.merge("synthesis_scripted_replies" => !@real))
    planned = Array(scenario["departments"]).map { |d| { "name" => d, "count" => 1 } }
    engagement = company.engagements.create!(status: "STAGE_1_ACTIVE", scope_type: "COMPANY", languages: ["en"],
                                             planned_departments: planned)
    people = {}
    Array(scenario["items"]).each_with_index do |item, i|
      who = item["person"] || "p#{i}"
      people[who] ||= company.employees.create!(
        display_name: item["name"] || "Participant #{who}", role_title: item["role"], department: item["department"],
        phone_e164: "+97150#{format('%07d', rand(10_000_000))}", participation_status: "completed",
        onboarding_step: "verified", preferred_language: "en"
      )
      company.findings.create!(
        employee: people[who], source_key: "eval-#{i}", department: item["department"], role_title: item["role"],
        area: item["title"], title: item["title"], what_happens_now: item["what"], friction: item["friction"],
        annual_hours_min: item.dig("hours", 0), annual_hours_max: item.dig("hours", 1), status: "approved",
        evidence: item["same_figures_as"] ? { "possible_duplicate_of" => company.findings.find_by!(source_key: "eval-#{item['same_figures_as']}").id } : {}
      )
    end
    leadership(scenario, engagement)
    [company, engagement]
  end

  def leadership(scenario, engagement)
    concerns = Array(scenario["leadership"])
    initiatives = Array(scenario["initiatives"])
    return if concerns.empty? && initiatives.empty?

    participant = engagement.participants.create!(company: engagement.company, participant_type: "KEY_PERSON",
                                                  name: "Leader", persona: "CEO_OWNER_MD")
    session = ConversationSession.create!(company: engagement.company, engagement: engagement, participant: participant,
                                          session_type: "KEY_PERSON", state: "COMPLETE")
    context = ManagementDiscoveryContext.create!(
      company: engagement.company, engagement: engagement, participant: participant, session: session,
      status: "COMPLETE", schema_version: "MDC.v1", persona: "CEO_OWNER_MD",
      content: { "concerns" => concerns.map { |c| { "text" => c["statement"], "evidence" => ["t2"] } } }
    )
    concerns.each do |c|
      context.strategic_findings.create!(company: engagement.company, engagement: engagement, category: c["category"] || "PROCESS",
                                         scope: "DEPARTMENT", statement: c["statement"], source_basis: "MANAGEMENT_STATEMENT",
                                         fact_status: "REPORTED", management_importance: c["importance"] || "HIGH",
                                         evidence: ["t2"])
    end
    initiatives.each do |i|
      context.planned_initiatives.create!(company: engagement.company, engagement: engagement,
                                          initiative_type: i["type"], description: i["description"], timing: i["timing"],
                                          status: i["status"] || "CONFIRMED", affected_areas: Array(i["affected_areas"]),
                                          evidence: ["t3"])
    end
  end

  # -- P10 -----------------------------------------------------------------------

  def check_pair(scenario, run, company)
    expect = scenario["expect"]
    items = Synthesis::WorkItems.call(company)
    pairs = Synthesis::Candidates.call(items)
    classifier = Synthesis::RelationshipClassifier.new(run, pairs, Synthesis.client_for(company), {})
    relationship = classifier.call.first
    failures = []
    critical = classifier.drops.count { |d| d["note"].match?(CRITICAL_P10) }
    failures << "#{critical} critical correction(s): #{classifier.drops.map { |d| d['note'] }.uniq.join(', ')}" if critical.positive?
    corrections = classifier.drops.map { |d| d["note"] }.reject { |n| n.match?(CRITICAL_P10) }.uniq
    puts format("  %-30s corrected: %s", scenario["name"], corrections.join(", ")) if corrections.any?

    grouped = relationship&.clusters? || false
    unless expect["clusters"].nil? || grouped == expect["clusters"]
      failures << "#{grouped ? 'grouped' : 'kept apart'}#{relationship ? " as #{relationship.relationship_type}/#{relationship.confidence}" : ' (not shortlisted)'}"
      critical += 1 if grouped && !expect["clusters"] && scenario["name_only"]
    end
    if relationship && expect["relationship_in"] && !expect["relationship_in"].include?(relationship.relationship_type)
      failures << "relationship #{relationship.relationship_type}, expected one of #{expect['relationship_in'].join('/')}"
      critical += 1 if expect["relationship_in"].include?("PROCESS_STAGE") && relationship.relationship_type == "DUPLICATE_WORK"
    end
    if relationship && expect["same_execution_in"] && !expect["same_execution_in"].include?(relationship.same_execution)
      failures << "P10 said same execution #{relationship.same_execution}, expected #{expect['same_execution_in'].join('/')}"
    end
    # Effort integrity (Doc 10 §25.2): what the platform counts, whatever P10 said.
    unless expect["counted_once"].nil? || relationship.nil?
      result = Synthesis::EffortNormalizer.call(items: items, edges: [Synthesis::Edge.from(relationship)])
      once = result.dedup_max < result.raw_max
      failures << "hours #{once ? 'counted once' : 'counted twice'} (#{relationship.relationship_type})" if once != expect["counted_once"]
      critical += 1 if !once && expect["counted_once"]
    end
    [failures, critical]
  end

  # -- P11 -----------------------------------------------------------------------

  def check_synthesis(scenario, run, company)
    expect = scenario["expect"]
    Synthesis::Run.call(run, client: Synthesis.client_for(company))
    run.reload
    engagement = run.engagement
    opportunities = ConsultancyOpportunity.current.where(engagement: engagement).to_a
    root_causes = RootCause.current.where(engagement: engagement).to_a
    validations = ManagementValidation.current.where(engagement: engagement).includes(:strategic_finding).to_a
    failures = []
    failures << "run #{run.status} (#{run.fallback_reason})" unless run.status == "COMPLETE"

    drops = Array(run.validation_drops).select { |d| d["stage"] == "P11" }
    critical = drops.count { |d| d["note"].match?(CRITICAL_P11) }
    if critical.positive?
      failures << "#{critical} critical drop(s): " +
                  drops.select { |d| d["note"].match?(CRITICAL_P11) }.map { |d| "#{d['where']} #{d['note']}" }.uniq.first(3).join("; ")
    end

    if (range = expect["root_causes"])
      count = root_causes.size
      failures << "#{count} root causes, expected #{range}" unless Range.new(*range.split("..").map(&:to_i)).cover?(count)
    end
    if (levels = expect["some_opportunity_level_in"]) && opportunities.none? { |o| levels.include?(o.level) }
      failures << "no opportunity at #{levels.join('/')} (got #{opportunities.map(&:level).uniq.join(', ').presence || 'none'})"
    end
    if (actions = expect["some_next_action_in"]) && opportunities.none? { |o| actions.include?(o.recommended_next_action) } &&
       Array(run.initiative_conflicts).none? { |c| %w[DEFER INTERIM_ONLY].include?(c["recommendation"]) }
      failures << "nothing deferred or interim (got #{opportunities.map(&:recommended_next_action).uniq.join(', ')})"
    end
    if expect["some_ai_relevance_none_or_training"] &&
       opportunities.none? { |o| o.ai_relevance == "NONE" || o.category == "TRAINING" }
      failures << "every opportunity leans on AI"
    end
    if (verdicts = expect["verdict_in"])
      got = validations.map(&:relationship)
      failures << "leadership verdict #{got.join(', ').presence || 'missing'}, expected #{verdicts.join('/')}" unless (got & verdicts).any?
    end
    if expect["coverage_note"] && Array(run.coverage_notes).empty?
      failures << "no coverage note"
    end
    if expect["no_company_wide"] && opportunities.any? { |o| o.level == "COMPANY_WIDE" }
      failures << "company-wide claim from one department"
      critical += 1
    end
    [failures, critical]
  end
end
