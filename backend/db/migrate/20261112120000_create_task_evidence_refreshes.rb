# frozen_string_literal: true

class CreateTaskEvidenceRefreshes < ActiveRecord::Migration[7.1]
  def change
    add_column :task_sources, :retired, :boolean, null: false, default: false

    create_table :task_evidence_refreshes do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.boolean :projection_pending, null: false, default: false
      t.bigint :source_generation, null: false, default: 0
      t.bigint :published_generation, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.datetime :retry_at
      t.string :failure_stage
      t.string :last_error_class
      t.datetime :last_failure_at
      t.datetime :last_published_at
      t.timestamps
      t.index :retry_at, where: "projection_pending OR source_generation > published_generation",
                        name: "index_task_evidence_refreshes_on_pending_retry"
    end
  end
end
