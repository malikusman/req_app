# frozen_string_literal: true

FactoryBot.define do
  factory :conversation do
    employee
    company { employee.company }
    status { "discovery" }
    question_count { 3 }
    last_activity_at { Time.current }
  end
end
