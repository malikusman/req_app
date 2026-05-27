# frozen_string_literal: true

FactoryBot.define do
  factory :subscription do
    company
    plan { "trial" }
    status { "trial" }
    trial_ends_at { 30.days.from_now }
    conversation_limit { 100 }
    conversations_used { 0 }
  end
end
