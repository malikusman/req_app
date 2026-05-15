# frozen_string_literal: true

class Phase7ImpersonationSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :impersonation_sessions do |t|
      t.references :platform_user, null: false, foreign_key: true
      t.references :company_user, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :token_jti, null: false
      t.datetime :expires_at, null: false
      t.datetime :ended_at
      t.string :ip_address
      t.timestamps
    end

    add_index :impersonation_sessions, :token_jti, unique: true
    add_index :impersonation_sessions, %i[platform_user_id ended_at]
  end
end
