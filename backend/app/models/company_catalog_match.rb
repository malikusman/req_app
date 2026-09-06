# frozen_string_literal: true

class CompanyCatalogMatch < ApplicationRecord
  belongs_to :company
  belongs_to :solution_catalog_entry, class_name: "SolutionCatalogEntry",
                                      foreign_key: :solution_catalog_entry_id
  belongs_to :recommendation, optional: true
  belongs_to :added_by_consultant, class_name: "ConsultantUser", foreign_key: :added_by_consultant_id, optional: true

  validates :score, :matched_at, presence: true

  scope :consultant_added, -> { where.not(added_by_consultant_id: nil) }
end
