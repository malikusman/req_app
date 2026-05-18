# frozen_string_literal: true

class CreateReportReviewTables < ActiveRecord::Migration[7.1]
  def change
    add_column :reports, :review_workflow_status, :string, default: "not_required", null: false
    add_column :reports, :reviews_completed_at, :datetime

    create_table :report_reviews do |t|
      t.references :report, null: false, foreign_key: true
      t.references :reviewer_user, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :status, default: "pending", null: false
      t.text :overall_note
      t.datetime :submitted_at
      t.timestamps
    end

    add_index :report_reviews, %i[report_id reviewer_user_id], unique: true

    create_table :report_review_section_states do |t|
      t.references :report_review, null: false, foreign_key: true
      t.string :section_key, null: false
      t.string :status, default: "pending", null: false
      t.timestamps
    end

    add_index :report_review_section_states, %i[report_review_id section_key],
              unique: true,
              name: "index_report_review_section_states_unique"

    create_table :report_review_comments do |t|
      t.references :report_review, null: false, foreign_key: true
      t.references :reviewer_user, null: false, foreign_key: true
      t.string :section_key, null: false
      t.text :body, null: false
      t.boolean :resolved, default: false, null: false
      t.timestamps
    end

    add_index :report_review_comments, %i[report_review_id section_key],
              name: "index_report_review_comments_on_review_and_section"
  end
end
