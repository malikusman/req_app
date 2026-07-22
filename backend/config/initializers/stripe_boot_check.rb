# frozen_string_literal: true

# BLK-5: Fail fast when Stripe billing is enabled without webhook signature verification.
# Skip in test so the suite can load without Stripe secrets; production/staging must set both.
if !Rails.env.test? && ENV["STRIPE_SECRET_KEY"].present? && ENV["STRIPE_WEBHOOK_SECRET"].blank?
  raise "STRIPE_WEBHOOK_SECRET is required when STRIPE_SECRET_KEY is set (BLK-5)."
end
