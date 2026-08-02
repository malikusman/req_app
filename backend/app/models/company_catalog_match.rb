# frozen_string_literal: true

class CompanyCatalogMatch < ApplicationRecord
  belongs_to :company
  belongs_to :solution_catalog_entry, class_name: "SolutionCatalogEntry",
                                      foreign_key: :solution_catalog_entry_id
  belongs_to :recommendation, optional: true
  belongs_to :added_by_reviewer, class_name: "ReviewerUser", foreign_key: :added_by_reviewer_id, optional: true

  validates :score, :matched_at, presence: true

  scope :reviewer_added, -> { where.not(added_by_reviewer_id: nil) }
end
