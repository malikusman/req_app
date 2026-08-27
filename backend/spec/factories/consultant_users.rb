# frozen_string_literal: true

FactoryBot.define do
  factory :consultant_user do
    sequence(:email) { |n| "consultant#{n}@example.com" }
    name { "Expert Consultant" }
    password { "password123" }
    status { "active" }
    jti { SecureRandom.uuid }

    trait :published_profile do
      headline { "Operations transformation · GCC" }
      bio { "A" * 80 }
      linkedin_url { "https://linkedin.com/in/expert" }
      expertise_tags { %w[Finance Controls Change\ management] }
      profile_status { "published" }
      profile_completed_at { Time.current }

      after(:create) do |consultant|
        create(:consultant_experience, consultant_user: consultant)
      end
    end
  end
end
