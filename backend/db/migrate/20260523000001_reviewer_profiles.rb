# frozen_string_literal: true

class ReviewerProfiles < ActiveRecord::Migration[7.1]
  def change
    change_table :reviewer_users, bulk: true do |t|
      t.string :avatar_storage_key
      t.string :headline, limit: 120
      t.text :bio
      t.string :linkedin_url
      t.string :website_url
      t.string :location
      t.string :timezone
      t.string :languages, array: true, default: [], null: false
      t.string :expertise_tags, array: true, default: [], null: false
      t.string :industries, array: true, default: [], null: false
      t.integer :years_experience
      t.jsonb :credentials, default: [], null: false
      t.string :profile_status, default: "draft", null: false
      t.datetime :profile_completed_at
      t.datetime :platform_verified_at
    end

    create_table :reviewer_experiences do |t|
      t.references :reviewer_user, null: false, foreign_key: true
      t.string :organization, null: false
      t.string :title, null: false
      t.integer :start_year, null: false
      t.integer :end_year
      t.string :summary, limit: 200
      t.integer :sort_order, default: 0, null: false
      t.timestamps
    end

    add_index :reviewer_users, :profile_status
    add_index :reviewer_experiences, %i[reviewer_user_id sort_order]
  end
end
