# frozen_string_literal: true

class FeatSignupRegistrations < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :approval_status, :string, null: false, default: "approved"
    add_column :companies, :approved_at, :datetime
    add_column :companies, :rejected_at, :datetime
    add_index :companies, :approval_status

    add_column :reviewer_users, :approved_at, :datetime
    add_column :reviewer_users, :rejected_at, :datetime
    add_column :reviewer_users, :application_notes, :text
    add_column :reviewer_users, :expertise_summary, :text

    create_table :company_registrations do |t|
      t.references :company, null: false, foreign_key: true
      t.references :company_user, null: false, foreign_key: true
      t.references :reviewed_by_platform_user, foreign_key: { to_table: :platform_users }
      t.string :company_name, null: false
      t.string :admin_name, null: false
      t.string :admin_email, null: false
      t.string :role_title
      t.text :notes
      t.string :status, null: false, default: "pending"
      t.text :review_note
      t.datetime :reviewed_at
      t.timestamps
    end

    add_index :company_registrations, :status
    add_index :company_registrations, :admin_email
  end
end
