# frozen_string_literal: true

FactoryBot.define do
  factory :discovery_playbook do
    department { "default" }
    version { 1 }
    prompt_block { "Ask workflow discovery questions." }
    active { true }
    activated_at { Time.current }
    association :created_by_platform_user, factory: :platform_user
  end
end
