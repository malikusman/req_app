# frozen_string_literal: true

FactoryBot.define do
  factory :reviewer_assignment do
    company
    reviewer_user
    assigned_by_platform_user factory: :platform_user
    status { "active" }
    assigned_at { Time.current }
  end
end
