# frozen_string_literal: true

class CatalogEntryAlias < ApplicationRecord
  belongs_to :solution_catalog_entry, class_name: "SolutionCatalogEntry",
                                      foreign_key: :solution_catalog_entry_id

  validates :alias_text, :normalized_alias, presence: true
end
