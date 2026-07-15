# frozen_string_literal: true

class SolutionCatalogEntry < ApplicationRecord
  self.table_name = "solution_catalog"

  CATEGORIES = %w[ai_agent automation integration saas].freeze
  TIERS = %w[none preferred sponsored].freeze
  ENTITY_TYPES = %w[tool app model agent integration service].freeze

  has_many :catalog_entry_aliases, foreign_key: :solution_catalog_entry_id, dependent: :destroy
  has_many :catalog_pricing_snapshots, foreign_key: :solution_catalog_entry_id, dependent: :destroy
  has_many :company_catalog_matches, foreign_key: :solution_catalog_entry_id, dependent: :destroy

  validates :name, :category, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :partnership_tier, inclusion: { in: TIERS }
  validates :entity_type, inclusion: { in: ENTITY_TYPES }, allow_nil: true

  before_validation :ensure_slug, on: :create

  scope :active, -> { where(active: true) }
  scope :published, -> { where(active: true).where.not(published_at: nil) }

  private

  def ensure_slug
    return unless has_attribute?(:slug)
    return if slug.present?

    base = name.to_s.parameterize.presence || "solution"
    candidate = base
    i = 1
    while self.class.where(slug: candidate).exists?
      i += 1
      candidate = "#{base}-#{i}"
    end
    self.slug = candidate
  end
end
