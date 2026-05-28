# frozen_string_literal: true

class ReportReviewReadyAndRelease < ActiveRecord::Migration[7.1]
  def change
    change_table :report_reviews, bulk: true do |t|
      t.datetime :ready_at
      t.text :ready_note
    end

    add_index :report_reviews, :ready_at
  end
end
