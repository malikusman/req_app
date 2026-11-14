# frozen_string_literal: true

require_relative "../demo_seeder"
require_relative "../discovery_simulator"
require_relative "../demo_company_interviews"
require_relative "../full_cycle_simulator"
require_relative "../demo_onboarding"
require_relative "../demo_key_person"
require_relative "../demo_pricing"

namespace :demo do
  desc "Dry-run the full discovery journey (onboarding → profiling → multi-agent interview → memory). PERSONA=finance_ic|hr_manager SLUG=acme-corp CLEANUP=1"
  task simulate: :environment do
    DiscoverySimulator.call
  end

  desc "Interview a whole demo company (Gulf Trading Co.) through the real path, answers improvised from fact sheets. ONLY=shiv,ravi"
  task company_interviews: :environment do
    DemoCompanyInterviews.call
  end

  desc "Company onboarding end to end on a demo company: set-up, website proposals, form, planning, submit. COMPANY_ID=3 REAL=1 WEBSITE=https://…"
  task onboarding: :environment do
    DemoOnboarding.call
  end

  desc "The key user's conversation with leadership end to end, after demo:onboarding: answers, scope card, document, context, hand-over to pricing. REAL=1 uses the model; FRESH=1 runs onboarding first"
  task key_person: :environment do
    DemoKeyPerson.call
  end

  desc "Stage 1 pricing end to end, after demo:key_person: proposal, P24, the administrator's correction and approval, the client's acceptance, team invitations up to the price and one beyond. REAL=1 uses the model for P24; FRESH=1 runs onboarding and the leadership conversation first"
  task pricing: :environment do
    DemoPricing.call
  end

  desc "Full product cycle: discovery + nudge + intelligence + report/PDF + reviewer follow-up. PERSONA=finance_ic|hr_manager SLUG=acme-corp CLEANUP=1"
  task full_cycle: :environment do
    FullCycleSimulator.call
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
