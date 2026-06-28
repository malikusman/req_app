# frozen_string_literal: true

FactoryBot.define do
  factory :reviewer_chat_message do
    company
    association :sender_reviewer_user, factory: :reviewer_user
    body { "Co-reviewer message" }
  end

  factory :review_discussion do
    report
    company { report.company }
    association :author_reviewer_user, factory: :reviewer_user
    target_type { "reviewer" }
    association :target_reviewer_user, factory: :reviewer_user
    anchor_type { "message" }
    anchor_id { "1" }
    body { "Can you clarify this point?" }
    status { "open" }
  end
end
