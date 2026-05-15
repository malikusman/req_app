# frozen_string_literal: true

class AccessCodeVerificationAttempt < ApplicationRecord
  belongs_to :company
  belongs_to :employee, optional: true

  FAILURE_REASONS = %w[invalid_code expired revoked unknown_phone].freeze
end
