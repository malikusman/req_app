# frozen_string_literal: true

FactoryBot.define do
  factory :platform_user do
    sequence(:email) { |n| "platform#{n}@example.com" }
    name { "Platform Admin" }
    password { "password123" }
    role { "super_admin" }
    jti { SecureRandom.uuid }
  end
end
