# frozen_string_literal: true

class ReviewerProfileReviewAndCv < ActiveRecord::Migration[7.1]
  def change
    change_table :reviewer_users, bulk: true do |t|
      t.string :cv_storage_key
      t.string :cv_filename
      t.string :cv_content_type
      t.bigint :cv_byte_size
    end
  end
end
