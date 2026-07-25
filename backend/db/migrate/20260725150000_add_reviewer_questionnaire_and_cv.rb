# frozen_string_literal: true

class AddReviewerQuestionnaireAndCv < ActiveRecord::Migration[7.1]
  def change
    add_column :reviewer_users, :questionnaire_answers, :jsonb, null: false, default: {}
    add_column :reviewer_users, :questionnaire_step, :integer, null: false, default: 1
    add_column :reviewer_users, :questionnaire_completed_at, :datetime
    add_column :reviewer_users, :cv_storage_key, :string
  end
end
