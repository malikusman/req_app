# frozen_string_literal: true

require_relative "../demo_seeder"
require_relative "../discovery_simulator"

namespace :demo do
  desc "Dry-run the full discovery journey (onboarding → profiling → multi-agent interview → memory). PERSONA=finance_ic|hr_manager SLUG=acme-corp CLEANUP=1"
  task simulate: :environment do
    DiscoverySimulator.call
  end

  desc "Seed full Acme Corp demo (employees, conversations, intelligence, report). SLUG=acme-corp"
  task seed: :environment do
    DemoSeeder.call(slug: ENV.fetch("SLUG", "acme-corp"))
    DemoScript.print_walkthrough
  end

  desc "Seed Beta Industries demo (expiring trial, report in review). SLUG=beta-industries"
  task seed_beta: :environment do
    BetaDemoSeeder.call(slug: ENV.fetch("SLUG", "beta-industries"))
    DemoScript.print_walkthrough
  end

  desc "Re-run all demo seeders (Acme + Beta)"
  task reset: :environment do
    DemoSeeder.call(slug: "acme-corp")
    BetaDemoSeeder.call(slug: "beta-industries")
    DemoScript.print_walkthrough
  end
end
