# frozen_string_literal: true

# The Stage 1 pricing benchmark (Doc 20 §22.2, P24 §9). Each scenario in
# spec/fixtures/pricing/scenarios builds an engagement, proposes its quote and
# has P24 explain it, then checks:
#
# - the calculator: the expected subtotal, complexity, floor status and risk
#   signals (Doc 17 §19)
# - P24: it was used rather than dropped, its derivation quotes every computed
#   amount exactly, the risks the platform flagged are named, and the client's
#   text carries nothing internal (ExplanationValidator's critical failures)
#
# Everything runs in a transaction that is rolled back. Without REAL=1 (or with
# SCRIPTED=1), P24 is scripted — which checks the plumbing, not the model;
# release decisions need the production model (Doc 05 §3.2).
#
#   rails pricing:eval                 # scripted
#   rails pricing:eval REAL=1 ONLY=standard,below_floor
class PricingEval
  DIR = Rails.root.join("spec/fixtures/pricing/scenarios")
  CONFIDENCE = %w[HIGH MEDIUM LOW].freeze

  def self.call(only: ENV["ONLY"], real: ENV["REAL"].present? && ENV["SCRIPTED"].blank?)
    new(only: only.to_s.split(",").map(&:strip).reject(&:empty?), real: real).call
  end

  def initialize(only:, real:)
    @only = only
    @real = real
  end

  def call
    scenarios = Dir[DIR.join("*.yml")].sort.map { |f| YAML.safe_load_file(f) }
    scenarios.select! { |s| @only.include?(s["name"]) } if @only.any?
    puts "Stage 1 pricing benchmark — #{@real ? 'the real model' : 'scripted P24'}, #{scenarios.size} scenarios"
    results = scenarios.map { |s| run(s) }
    passed = results.count { |r| r[:failures].empty? }
    puts ""
    puts "#{passed}/#{results.size} passed"
    results
  end

  private

  def run(scenario)
    failures = []
    ActiveRecord::Base.transaction do
      quote = propose(scenario)
      failures.concat(check_figures(scenario, quote))
      failures.concat(check_p24(quote))
      raise ActiveRecord::Rollback
    end
    puts format("  %-26s %s", scenario["name"], failures.empty? ? "pass" : "FAIL — #{failures.join('; ')}")
    { name: scenario["name"], failures: failures }
  rescue StandardError => e
    puts format("  %-26s ERROR — %s: %s", scenario["name"], e.class, e.message)
    { name: scenario["name"], failures: [e.message] }
  end

  def propose(scenario)
    Pricing::Defaults.ensure!
    # Rolled back with the rest: this scenario is about having none.
    Quote.stage1.where(status: "ACCEPTED").update_all(status: "SUPERSEDED") if scenario["no_comparables"]
    if scenario["floor"]
      MarginFloorVersion.create!(version: MarginFloorVersion.next_version, value: BigDecimal(scenario["floor"]),
                                 effective_from: 1.minute.ago, reason: "Benchmark: #{scenario['name']}")
    end
    company = Company.create!(name: "Benchmark #{scenario['name']}", slug: "pricing-eval-#{SecureRandom.hex(4)}",
                              company_profile: { "country" => "UAE", "locations" => scenario["locations"],
                                                 "industry" => "wholesale_distribution" },
                              settings: Company::DEFAULT_SETTINGS.merge("pricing_scripted_replies" => !@real))
    departments = scenario["departments"].map { |name, count| { "name" => name, "count" => count } }
    engagement = company.engagements.create!(status: "STAGE_1_PRICING", scope_type: "COMPANY",
                                             languages: scenario["languages"], planned_departments: departments)
    scenario["named"].to_i.times do |i|
      engagement.participants.create!(company: company, participant_type: "EMPLOYEE", name: "Person #{i + 1}")
    end
    quote = Pricing::ProposeStage1.call(engagement, reason: "benchmark").quote
    Pricing::Explainer.call(quote, client: Pricing.client_for(company))
    quote.reload
  end

  def check_figures(scenario, quote)
    want = scenario.fetch("expect", {})
    risks = quote.estimate["risk_signals"].map { |s| s["code"] }
    failures = []
    failures << "subtotal #{quote.subtotal.to_s('F')}, wanted #{want['subtotal']}" if want["subtotal"] && quote.subtotal.to_s("F") != want["subtotal"]
    complexity = quote.line_items.find { |l| l["key"] == "complexity" }&.dig("amount")
    failures << "complexity #{complexity}, wanted #{want['complexity']}" if want["complexity"] && complexity != want["complexity"]
    failures << "below floor #{quote.below_floor}, wanted #{want['below_floor']}" if want.key?("below_floor") && quote.below_floor != want["below_floor"]
    Array(want["risks"]).each { |code| failures << "risk #{code} not flagged" unless risks.include?(code) }
    if (cap = want["confidence_at_most"]) && CONFIDENCE.index(quote.estimate["confidence"]) < CONFIDENCE.index(cap)
      failures << "confidence #{quote.estimate['confidence']}, wanted at most #{cap}"
    end
    failures
  end

  def check_p24(quote)
    return ["P24 dropped (#{quote.events.find_by(event: 'explanation_fallback')&.detail})"] unless quote.explanation_source == "P24"

    failures = []
    quoted = Array(quote.admin_explanation["derivation"]).map { |d| d["amount"] }
    quote.line_items.each do |line|
      amount = Pricing::Money.format(line["amount"], quote.currency)
      failures << "derivation doesn't quote #{amount}" unless quoted.include?(amount)
    end
    if quote.estimate["risk_signals"].any? && Array(quote.admin_explanation["what_could_make_this_wrong"]).empty?
      failures << "no risks named"
    end
    failures
  end
end
