# frozen_string_literal: true

FactoryBot.define do
  factory :reviewer_user do
    sequence(:email) { |n| "reviewer#{n}@example.com" }
    name { "Expert Reviewer" }
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
      platform_verified_at { Time.current }

      after(:create) do |reviewer|
        create(:reviewer_experience, reviewer_user: reviewer)
      end
    end
  end
end
