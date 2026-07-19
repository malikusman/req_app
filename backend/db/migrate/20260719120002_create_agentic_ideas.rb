# frozen_string_literal: true

class CreateAgenticIdeas < ActiveRecord::Migration[7.1]
  def change
    create_table :agentic_ideas do |t|
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.text :summary
      t.text :system_fit
      t.text :value_time
      t.text :value_efficiency
      t.text :value_cost
      t.string :approx_timeline
      t.string :estimated_cost
      t.float :confidence, null: false, default: 0.5
      t.string :status, null: false, default: "draft"
      t.string :source, null: false, default: "generated"
      t.jsonb :related_signal_ids, null: false, default: []
      t.jsonb :related_pattern_ids, null: false, default: []
      t.jsonb :related_stack_ids, null: false, default: []
      t.references :solution_catalog_entry, foreign_key: { to_table: :solution_catalog }
      t.string :created_by_type
      t.bigint :created_by_id
      t.string :updated_by_type
      t.bigint :updated_by_id
      t.datetime :published_at

      t.timestamps
    end

    add_index :agentic_ideas, %i[company_id status]
    add_index :agentic_ideas, %i[company_id title]
    add_index :agentic_ideas, %i[created_by_type created_by_id], name: "index_agentic_ideas_on_created_by"
  end
end
