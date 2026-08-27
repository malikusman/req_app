# frozen_string_literal: true

FactoryBot.define do
  factory :consultant_chat_message do
    company
    association :sender_consultant_user, factory: :consultant_user
    body { "Co-consultant message" }
  end

  factory :review_discussion do
    report
    company { report.company }
    association :author_consultant_user, factory: :consultant_user
    target_type { "consultant" }
    association :target_consultant_user, factory: :consultant_user
    anchor_type { "message" }
    anchor_id { "1" }
    body { "Can you clarify this point?" }
    status { "open" }
  end
end
