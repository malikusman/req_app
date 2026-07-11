# frozen_string_literal: true

class CompanyCatalogMatch < ApplicationRecord
  belongs_to :company
  belongs_to :solution_catalog_entry, class_name: "SolutionCatalogEntry",
                                      foreign_key: :solution_catalog_entry_id
  belongs_to :recommendation, optional: true

  validates :score, :matched_at, presence: true
end
