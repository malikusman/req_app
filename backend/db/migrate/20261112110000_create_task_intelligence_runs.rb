# frozen_string_literal: true

class CreateTaskIntelligenceRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :task_intelligence_runs do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.integer :version, null: false
      t.integer :target_size, null: false
      t.string :algorithm_version, null: false
      t.string :evaluation_mode, null: false
      t.string :fingerprint, null: false
      t.timestamps
      t.index %i[company_id version], unique: true
    end

    create_table :task_candidate_proposals do |t|
      t.references :task_intelligence_run, null: false, foreign_key: { on_delete: :cascade }
      t.references :process_cluster_revision, null: false, foreign_key: { on_delete: :cascade }
      t.text :title, null: false
      t.string :disposition, null: false
      t.text :disposition_reason, null: false
      t.integer :rank
      t.integer :score, null: false
      t.string :priority, null: false
      t.string :confidence, null: false
      t.jsonb :assessment, null: false
      t.timestamps
      t.index %i[task_intelligence_run_id process_cluster_revision_id], unique: true,
              name: "index_task_candidate_proposals_on_run_and_cluster_revision"
      t.index %i[task_intelligence_run_id rank], unique: true, where: "rank IS NOT NULL"
    end
  end
end
