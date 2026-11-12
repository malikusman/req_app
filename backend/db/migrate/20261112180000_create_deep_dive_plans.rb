# frozen_string_literal: true

class CreateDeepDivePlans < ActiveRecord::Migration[7.1]
  def change
    create_table :deep_dive_plans do |t|
      t.references :task_selection_revision, null: false, foreign_key: true
      t.string :task_key, null: false
      t.string :status, null: false
      t.string :generation_token, null: false
      t.text :generation_error
      t.jsonb :context, null: false
      t.timestamps
      t.index %i[task_selection_revision_id task_key], unique: true
      t.check_constraint "status IN ('queued', 'generating', 'failed', 'draft', 'approved')", name: "deep_dive_plan_status"
    end

    create_table :deep_dive_plan_revisions do |t|
      t.references :deep_dive_plan, null: false, foreign_key: true
      t.references :consultant_user, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :action, null: false
      t.text :reason, null: false
      t.jsonb :content, null: false
      t.timestamps
      t.index %i[deep_dive_plan_id version], unique: true
      t.check_constraint "version > 0 AND action IN ('generated', 'edited', 'approved')", name: "deep_dive_plan_revision_valid"
    end
  end
end
