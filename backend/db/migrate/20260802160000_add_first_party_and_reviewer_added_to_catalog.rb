# frozen_string_literal: true

class AddFirstPartyAndReviewerAddedToCatalog < ActiveRecord::Migration[7.1]
  def change
    # Platform can mark which catalog products are first-party (built by us) vs
    # curated third-party tools — the catalog is a mix of both.
    add_column :solution_catalog, :first_party, :boolean, null: false, default: false

    # Attribution when a reviewer adds a product to a company's list.
    add_column :company_catalog_matches, :added_by_reviewer_id, :bigint
    add_foreign_key :company_catalog_matches, :reviewer_users, column: :added_by_reviewer_id
    add_index :company_catalog_matches, :added_by_reviewer_id
  end
end
