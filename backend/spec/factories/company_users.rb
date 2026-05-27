# frozen_string_literal: true

FactoryBot.define do
  factory :company_user do
    company
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "Test User" }
    password { "password123" }
    role { "company_admin" }
    status { "active" }
    jti { SecureRandom.uuid }
  end
end
