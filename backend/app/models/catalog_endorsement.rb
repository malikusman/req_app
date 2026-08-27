# frozen_string_literal: true

class CatalogEndorsement < ApplicationRecord
  belongs_to :company
  belongs_to :report, optional: true
  belongs_to :consultant_user
  belongs_to :solution_catalog_entry, class_name: "SolutionCatalogEntry", optional: true,
                                      foreign_key: :solution_catalog_entry_id

  DISPOSITIONS = %w[endorse reject suggest].freeze
  validates :disposition, inclusion: { in: DISPOSITIONS }
end
