# frozen_string_literal: true

class CreateCompanySystems < ActiveRecord::Migration[7.1]
  def change
    create_table :company_systems do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.string :category, null: false, default: "other"
      t.string :source, null: false, default: "manual"
      t.float :confidence, null: false, default: 1.0
      t.boolean :active, null: false, default: true
      t.text :notes

      t.timestamps
    end

    add_index :company_systems, %i[company_id normalized_name], unique: true
    add_index :company_systems, %i[company_id active]
  end
end
