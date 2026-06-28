# frozen_string_literal: true

class CreateReviewDiscussions < ActiveRecord::Migration[7.1]
  def change
    create_table :review_discussions do |t|
      t.references :report, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :author_reviewer_user, null: false, foreign_key: { to_table: :reviewer_users }
      t.references :target_reviewer_user, foreign_key: { to_table: :reviewer_users }
      t.references :employee, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :parent, foreign_key: { to_table: :review_discussions }
      t.string :target_type, null: false
      t.string :anchor_type, null: false
      t.string :anchor_id, null: false
      t.text :body, null: false
      t.string :status, null: false, default: "open"
      t.timestamps
    end

    add_index :review_discussions, %i[report_id anchor_type anchor_id], name: "idx_review_discussions_report_anchor"
    add_index :review_discussions, %i[report_id parent_id], name: "idx_review_discussions_report_parent"

    add_reference :reviewer_info_requests, :message, foreign_key: true
    add_reference :reviewer_info_requests, :review_discussion, foreign_key: true
  end
end
