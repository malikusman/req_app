# frozen_string_literal: true

FactoryBot.define do
  factory :message do
    conversation
    direction { "inbound" }
    message_type { "text" }
    sequence(:body) { |n| "Message #{n}" }
    reviewer_followup { false }
    is_discovery_question { false }
  end
end
