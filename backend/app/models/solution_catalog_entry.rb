# frozen_string_literal: true

class SolutionCatalogEntry < ApplicationRecord
  self.table_name = "solution_catalog"

  CATEGORIES = %w[ai_agent automation integration saas].freeze
  TIERS = %w[none preferred sponsored].freeze

  validates :name, :category, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :partnership_tier, inclusion: { in: TIERS }

  scope :active, -> { where(active: true) }
end
