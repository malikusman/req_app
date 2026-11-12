# frozen_string_literal: true

class CreateClarificationRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :clarification_requests do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.references :left_source, null: false, foreign_key: { to_table: :task_sources, on_delete: :cascade }
      t.references :right_source, null: false, foreign_key: { to_table: :task_sources, on_delete: :cascade }
      t.string :pair_key, null: false
      t.string :status, null: false
      t.integer :version, null: false
      t.jsonb :details, null: false
      t.jsonb :history, null: false, default: []
      t.timestamps

      t.index %i[company_id pair_key], unique: true
    end
  end
end
