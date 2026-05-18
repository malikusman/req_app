# frozen_string_literal: true

class CreateReviewerAssignments < ActiveRecord::Migration[7.1]
  def change
    create_table :reviewer_assignments do |t|
      t.references :reviewer_user, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :assigned_by_platform_user, null: false, foreign_key: { to_table: :platform_users }
      t.string :status, default: "active", null: false
      t.datetime :assigned_at, null: false
      t.datetime :removed_at
      t.timestamps
    end

    add_index :reviewer_assignments, %i[company_id reviewer_user_id],
              unique: true,
              where: "status = 'active'",
              name: "index_reviewer_assignments_active_unique"
  end
end
