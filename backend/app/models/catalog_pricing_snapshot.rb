# frozen_string_literal: true

class CatalogPricingSnapshot < ApplicationRecord
  belongs_to :solution_catalog_entry, class_name: "SolutionCatalogEntry",
                                      foreign_key: :solution_catalog_entry_id
end
