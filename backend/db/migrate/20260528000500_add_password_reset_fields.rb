# frozen_string_literal: true

class AddPasswordResetFields < ActiveRecord::Migration[7.1]
  def change
    change_table :company_users, bulk: true do |t|
      t.string :password_reset_token_digest
      t.datetime :password_reset_sent_at
    end
    add_index :company_users, :password_reset_token_digest, unique: true

    change_table :reviewer_users, bulk: true do |t|
      t.string :password_reset_token_digest
      t.datetime :password_reset_sent_at
    end
    add_index :reviewer_users, :password_reset_token_digest, unique: true
  end
end
