# frozen_string_literal: true

class CreateCompanyMemoryFacts < ActiveRecord::Migration[7.1]
  def change
    create_table :company_memory_facts do |t|
      t.references :company, null: false, foreign_key: true
      t.references :employee, foreign_key: true
      t.references :conversation, foreign_key: true
      t.string :fact_type, null: false, default: "finding"
      t.string :department
      t.text :content, null: false
      t.float :confidence
      t.string :source_agent
      t.vector :embedding, limit: 1536
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :company_memory_facts, [:company_id, :fact_type]
    add_index :company_memory_facts, [:company_id, :department]
  end
end
