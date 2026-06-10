# frozen_string_literal: true

FactoryBot.define do
  factory :platform_audit_log do
    platform_user
    action { "company_created" }
    target_type { "Company" }
    target_id { 1 }
    metadata { {} }
    ip_address { "127.0.0.1" }
  end
end
