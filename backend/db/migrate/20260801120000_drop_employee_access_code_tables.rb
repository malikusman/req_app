# frozen_string_literal: true

class DropEmployeeAccessCodeTables < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE employees
      SET onboarding_step = CASE
        WHEN display_name IS NOT NULL AND display_name != '' THEN 'awaiting_consent'
        ELSE 'awaiting_name'
      END
      WHERE onboarding_step = 'awaiting_access_code'
    SQL

    execute <<~SQL.squish
      UPDATE employees
      SET verified_at = COALESCE(verified_at, CURRENT_TIMESTAMP)
      WHERE onboarding_step = 'awaiting_consent' AND verified_at IS NULL
    SQL

    drop_table :access_code_verification_attempts, if_exists: true
    drop_table :employee_access_codes, if_exists: true
  end

  def down
    create_table :employee_access_codes do |t|
      t.bigint :employee_id, null: false
      t.bigint :company_id, null: false
      t.string :code_digest, null: false
      t.string :code_hint_last_two
      t.string :status, default: "active", null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :revoked_at
      t.string :issued_by_type, default: "system", null: false
      t.string :code_plaintext
      t.timestamps
    end
    add_index :employee_access_codes, :company_id
    add_index :employee_access_codes, :employee_id
    add_index :employee_access_codes, [:employee_id, :status]
    add_foreign_key :employee_access_codes, :companies
    add_foreign_key :employee_access_codes, :employees

    create_table :access_code_verification_attempts do |t|
      t.bigint :company_id, null: false
      t.string :phone_e164, null: false
      t.bigint :employee_id
      t.boolean :success, default: false, null: false
      t.string :failure_reason
      t.string :ip_address
      t.timestamps
    end
    add_index :access_code_verification_attempts, :company_id
    add_index :access_code_verification_attempts, :employee_id
    add_index :access_code_verification_attempts, [:company_id, :created_at]
    add_foreign_key :access_code_verification_attempts, :companies
    add_foreign_key :access_code_verification_attempts, :employees
  end
end
