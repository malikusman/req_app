# frozen_string_literal: true

FactoryBot.define do
  factory :employee_nudge do
    employee
    company_user { association :company_user, company: employee.company }
    sent_at { Time.current }
    meta_message_id { "dev-#{SecureRandom.hex(4)}" }
  end
end
