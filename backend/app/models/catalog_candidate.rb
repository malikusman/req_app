# frozen_string_literal: true

class CatalogCandidate < ApplicationRecord
  belongs_to :catalog_source_record, optional: true
  belongs_to :suggested_catalog_entry, class_name: "SolutionCatalogEntry", optional: true
  belongs_to :reviewed_by_platform_user, class_name: "PlatformUser", optional: true
  has_many :employee_market_alerts, dependent: :destroy

  STATUSES = %w[pending approved rejected merged].freeze
  ANALYSIS_STATUSES = %w[pending analyzed stale archived].freeze
  ENTITY_TYPES = %w[tool news model other].freeze

  validates :name, presence: true
  validates :review_status, inclusion: { in: STATUSES }
  validates :analysis_status, inclusion: { in: ANALYSIS_STATUSES }
  validates :entity_type, inclusion: { in: ENTITY_TYPES }, allow_blank: true

  scope :pending_review, -> { where(review_status: "pending") }
  scope :analyzed, -> { where(analysis_status: "analyzed") }
  scope :emailable, -> {
    analyzed.where("COALESCE(provenance->>'stub', 'false') != 'true'")
  }

  def stub?
    provenance.is_a?(Hash) && provenance["stub"] == true
  end

  def source_url
    website_url.presence || provenance&.dig("source_url") || catalog_source_record&.url
  end
end
