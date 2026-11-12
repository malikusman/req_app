# frozen_string_literal: true

class CreateTaskSelectionReviews < ActiveRecord::Migration[7.1]
  def change
    create_table :task_selection_reviews do |t|
      t.references :company, null: false, foreign_key: true
      t.references :task_intelligence_run, null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end

    create_table :task_selection_revisions do |t|
      t.references :task_selection_review, null: false, foreign_key: true
      t.references :consultant_user, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :action, null: false
      t.text :reason, null: false
      t.string :status, null: false
      t.jsonb :snapshot, null: false
      t.timestamps

      t.index %i[task_selection_review_id version], unique: true
      t.check_constraint "version > 0", name: "task_selection_positive_version"
      t.check_constraint "status IN ('draft', 'finalized')", name: "task_selection_revision_status"
    end
  end
end
