# frozen_string_literal: true

class CatalogSyncRun < ApplicationRecord
  belongs_to :catalog_source
  has_many :catalog_source_records, dependent: :nullify

  STATUSES = %w[running success partial failed].freeze
  validates :status, inclusion: { in: STATUSES }
end
