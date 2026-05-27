# frozen_string_literal: true

FactoryBot.define do
  factory :company do
    sequence(:name) { |n| "Test Company #{n}" }
    sequence(:slug) { |n| "test-company-#{n}" }
    display_name { name }
    locale { "en" }
    settings { Company::DEFAULT_SETTINGS }
    report_readiness_breakdown do
      {
        "employees_interviewed" => 0,
        "departments_represented" => 0,
        "confirmed_patterns" => 0,
        "multimodal_contributions" => 0
      }
    end

    trait :onboarded do
      portal_onboarding_completed_at { Time.current }
    end

    after(:create) do |company|
      create(:subscription, company: company) unless company.subscription
    end
  end
end
