# frozen_string_literal: true

# The company-owned-solutions concept was replaced by platform-owned products in
# the solution catalog (with reviewer add-from-catalog). Drop the now-unused
# company_systems columns.
class RemoveOwnedSolutionFieldsFromCompanySystems < ActiveRecord::Migration[7.1]
  def up
    remove_foreign_key :company_systems, column: :reviewer_user_id, if_exists: true
    remove_index :company_systems, column: %i[company_id kind], if_exists: true
    remove_column :company_systems, :kind, if_exists: true
    remove_column :company_systems, :description, if_exists: true
    remove_column :company_systems, :capabilities, if_exists: true
    remove_column :company_systems, :reviewer_endorsed, if_exists: true
    remove_column :company_systems, :reviewer_note, if_exists: true
    remove_column :company_systems, :reviewer_user_id, if_exists: true
  end

  def down
    change_table :company_systems, bulk: true do |t|
      t.string :kind, null: false, default: "system"
      t.text :description
      t.text :capabilities
      t.boolean :reviewer_endorsed, null: false, default: false
      t.text :reviewer_note
      t.bigint :reviewer_user_id
    end
    add_index :company_systems, %i[company_id kind]
    add_foreign_key :company_systems, :reviewer_users, column: :reviewer_user_id
  end
end
