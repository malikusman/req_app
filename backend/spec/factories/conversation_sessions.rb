# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_session do
    participant { association :engagement_participant, participant_type: "KEY_PERSON" }
    engagement { participant.engagement }
    company { participant.company }
    session_type { "KEY_PERSON" }
  end

  factory :conversation_turn do
    session { association :conversation_session }
    sequence(:turn_index) { |n| n }
    direction { "PARTICIPANT" }
    text { "We want to grow into Saudi in the next two years." }
  end
end
