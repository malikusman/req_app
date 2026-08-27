# frozen_string_literal: true

FactoryBot.define do
  factory :consultant_assignment do
    company
    consultant_user
    assigned_by_platform_user factory: :platform_user
    status { "active" }
    assigned_at { Time.current }
  end
end
