# frozen_string_literal: true

class AddOwnedSolutionFieldsToCompanySystems < ActiveRecord::Migration[7.1]
  def change
    change_table :company_systems, bulk: true do |t|
      t.string :kind, null: false, default: "system"   # system | owned_solution
      t.text :description                                # what the owned solution does
      t.text :capabilities                               # capabilities / what it addresses
      t.boolean :reviewer_endorsed, null: false, default: false
      t.text :reviewer_note
      t.bigint :reviewer_user_id
    end

    add_index :company_systems, %i[company_id kind]
    add_foreign_key :company_systems, :reviewer_users, column: :reviewer_user_id
  end
end
