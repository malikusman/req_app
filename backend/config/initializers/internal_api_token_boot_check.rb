# frozen_string_literal: true

# HIGH-3: Never boot production without an explicit internal API token.
if Rails.env.production? && ENV["INTERNAL_API_TOKEN"].to_s.strip.blank?
  raise "INTERNAL_API_TOKEN is required in production (HIGH-3)."
end
