# frozen_string_literal: true

class CreateReviewerUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :reviewer_users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.string :status, default: "active", null: false
      t.string :jti, null: false
      t.timestamps
    end

    add_index :reviewer_users, :email, unique: true
    add_index :reviewer_users, :jti, unique: true
  end
end
