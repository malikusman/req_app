# frozen_string_literal: true

require_relative "../scenario_cycle_runner"
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
end
