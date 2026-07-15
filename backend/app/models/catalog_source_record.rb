# frozen_string_literal: true

class CatalogSourceRecord < ApplicationRecord
  belongs_to :catalog_source
  belongs_to :catalog_sync_run, optional: true
  has_many :catalog_candidates, dependent: :nullify

  validates :external_id, :fingerprint, :fetched_at, presence: true
end
