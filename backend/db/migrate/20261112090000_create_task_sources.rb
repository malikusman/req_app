# frozen_string_literal: true

class CreateTaskSources < ActiveRecord::Migration[7.1]
  def change
    create_table :task_sources do |t|
      t.references :company, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :finding, foreign_key: { on_delete: :nullify }
      t.string :source_kind, null: false
      t.string :local_task_id, null: false
      t.text :name, null: false
      t.text :description
      t.integer :discovery_revision
      t.integer :version, null: false
      t.jsonb :source_snapshot, null: false
      t.jsonb :evidence_references, null: false, default: []
      t.timestamps
    end

    add_index :task_sources, %i[conversation_id source_kind local_task_id version],
              unique: true, name: "index_task_sources_on_local_identity_and_version"
  end
end
