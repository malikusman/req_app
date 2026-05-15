# frozen_string_literal: true

class Pattern < ApplicationRecord
  belongs_to :company

  STATUSES = %w[emerging confirmed].freeze

  validates :title, :first_seen_at, :last_updated_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :confirmed, -> { where(status: "confirmed") }
end
