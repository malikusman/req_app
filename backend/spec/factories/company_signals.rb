# frozen_string_literal: true

FactoryBot.define do
  factory :company_signal do
    company
    sequence(:label) { |n| "Signal #{n}" }
    signal_type { "manual_process" }
    strength { 0.8 }
    departments { ["finance"] }
    evidence_count { 2 }
    status { "emerging" }
    first_seen_at { Time.current }
    last_updated_at { Time.current }
    metadata { {} }
  end
end
