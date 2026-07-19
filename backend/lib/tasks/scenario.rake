# frozen_string_literal: true

require_relative "../scenario_cycle_runner"
require_relative "../docs_only_scenario_runner"
require_relative "../discovery_simulator"

namespace :scenario do
  desc "Provision scenario-corp and run evidence-to-action full-cycle checks. CLEANUP=1 to purge sim employee afterward."
  task full_cycle: :environment do
    ScenarioCycleRunner.call(cleanup: ENV["CLEANUP"] == "1")
  end

  desc "Submit pending Scenario Corp reviews (if needed), regenerate PDF, and assert live appendix HTML. Skips rediscovery."
  task verify_appendix: :environment do
    ScenarioCycleRunner.verify_appendix!
  end

  desc "Docs-first Scenario A: zero employees + documents → baseline intelligence + report"
  task docs_only: :environment do
    DocsOnlyScenarioRunner.docs_only!(cleanup: ENV["CLEANUP"] == "1")
  end

  desc "Docs-first Scenario A→B: employees later; assert signals accumulate (IDs preserved)"
  task docs_then_employees: :environment do
    DocsOnlyScenarioRunner.docs_then_employees!(cleanup: ENV["CLEANUP"] == "1")
  end
end
