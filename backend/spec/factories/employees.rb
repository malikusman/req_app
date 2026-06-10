# frozen_string_literal: true

FactoryBot.define do
  factory :employee do
    company
    sequence(:phone_e164) { |n| "+1415#{format('%07d', 5_000_000 + n)}" }
    display_name { "Test Employee" }
    department { "operations" }
    participation_status { "started" }
    onboarding_step { "verified" }
    preferred_language { "en" }
  end
end
