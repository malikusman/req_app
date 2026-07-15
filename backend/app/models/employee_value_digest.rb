# frozen_string_literal: true

class EmployeeValueDigest < ApplicationRecord
  belongs_to :employee
  belongs_to :company

  STATUSES = %w[draft reviewed sent failed suppressed].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :period_key, presence: true
end
