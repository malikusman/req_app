# frozen_string_literal: true

FactoryBot.define do
  factory :engagement do
    company
    status { "STAGE_1_ACTIVE" }
    scope_type { "COMPANY" }
    languages { ["en"] }
  end

  factory :engagement_participant do
    engagement
    company { engagement.company }
    participant_type { "EMPLOYEE" }
    sequence(:name) { |n| "Participant #{n}" }
  end
end
