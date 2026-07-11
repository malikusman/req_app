# frozen_string_literal: true

class CatalogSource < ApplicationRecord
  has_many :catalog_sync_runs, dependent: :destroy
  has_many :catalog_source_records, dependent: :destroy

  SOURCE_TYPES = %w[rss api scrape manual_feed].freeze

  validates :name, :source_type, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }

  scope :active, -> { where(active: true) }
end
