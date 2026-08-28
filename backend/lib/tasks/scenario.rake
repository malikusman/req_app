# frozen_string_literal: true

require_relative "../scenario_cycle_runner"
require_relative "../docs_only_scenario_runner"
require_relative "../gulflink_scenario_runner"
require_relative "../discovery_simulator"
require_relative "../companion_scenario_runner"
require_relative "../nimbus_scenario_runner"

namespace :scenario do
  desc "Nimbus Trading Co: full-app run — admin+client+consultant, employees on WhatsApp+web, docs, " \
       "dossier-driven discovery, handover package, consultant amends + states a need, gated report, approval. " \
       "NIMBUS_MAX_EMPLOYEES / NIMBUS_MAX_QUESTIONS / NIMBUS_MIN_QUESTIONS to size a run; CLEANUP=1 to purge sim employees."
  task nimbus: :environment do
    NimbusScenarioRunner.call(cleanup: ENV["CLEANUP"] == "1")
  end

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

  desc "GulfLink Logistics (Dubai): docs → McKinsey reviewer → Q&A → report + OBSERVATIONS.md"
  task gulflink: :environment do
    GulflinkScenarioRunner.call(cleanup: ENV["CLEANUP"] == "1")
  end

  desc "Post-discovery companion eval (LM Studio). LIVE=1 WRITE=1 ALLOW_MOCKS=0 required for live scoring."
  task companion: :environment do
    CompanionScenarioRunner.call(live: ENV["LIVE"] == "1", write: ENV.fetch("WRITE", "1") == "1")
  end
end
