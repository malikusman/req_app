# frozen_string_literal: true

class Phase7EmployeeWebDiscovery < ActiveRecord::Migration[7.1]
  def change
    add_column :employees, :preferred_channel, :string, default: "whatsapp", null: false

    create_table :employee_web_sessions do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :verified_at
      t.datetime :last_seen_at
      t.string :ip_address
      t.timestamps
    end

    add_index :employee_web_sessions, :token_digest, unique: true
    add_index :employee_web_sessions, %i[employee_id expires_at]
  end
end
