# frozen_string_literal: true

class CreateProcessClusters < ActiveRecord::Migration[7.1]
  def change
    create_table :process_clusters do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.string :anchor_key, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index %i[company_id anchor_key], unique: true
    end

    create_table :process_cluster_revisions do |t|
      t.references :process_cluster, null: false, foreign_key: { on_delete: :cascade }
      t.integer :number, null: false
      t.string :status, null: false
      t.string :confidence, null: false
      t.text :rationale, null: false
      t.string :fingerprint, null: false
      t.jsonb :relationships, null: false, default: []
      t.jsonb :effort_summary, null: false, default: {}
      t.timestamps
      t.index %i[process_cluster_id number], unique: true
    end

    create_table :process_cluster_memberships do |t|
      t.references :process_cluster_revision, null: false, foreign_key: { on_delete: :cascade }
      t.references :task_source, null: false, foreign_key: { on_delete: :cascade }
      t.jsonb :effort_observations, null: false, default: []
      t.timestamps
      t.index %i[process_cluster_revision_id task_source_id], unique: true,
              name: "index_process_cluster_memberships_on_revision_and_source"
    end
  end
end
