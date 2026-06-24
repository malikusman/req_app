# frozen_string_literal: true

FactoryBot.define do
  factory :employee_web_session do
    employee
    company { employee.company }
    token_digest { Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)) }
    expires_at { 14.days.from_now }
  end
end
