# frozen_string_literal: true

FactoryBot.define do
  factory :message do
    conversation
    direction { "inbound" }
    message_type { "text" }
    sequence(:body) { |n| "Message #{n}" }
    consultant_followup { false }
    is_discovery_question { false }
  end
end
