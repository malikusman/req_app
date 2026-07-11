# frozen_string_literal: true

class CatalogCandidate < ApplicationRecord
  belongs_to :catalog_source_record, optional: true
  belongs_to :suggested_catalog_entry, class_name: "SolutionCatalogEntry", optional: true
  belongs_to :reviewed_by_platform_user, class_name: "PlatformUser", optional: true

  STATUSES = %w[pending approved rejected merged].freeze
  validates :name, presence: true
  validates :review_status, inclusion: { in: STATUSES }

  scope :pending_review, -> { where(review_status: "pending") }
end
