class CreateCoreSchema < ActiveRecord::Migration[7.1]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :display_name
      t.string :logo_storage_key
      t.string :locale, default: "en", null: false
      t.datetime :portal_onboarding_completed_at
      t.datetime :pin_rotated_at
      t.float :report_readiness_score, default: 0.0, null: false
      t.jsonb :settings, default: {}, null: false
      t.jsonb :report_readiness_breakdown, default: {}, null: false
      t.jsonb :intelligence_snapshot, default: {}, null: false
      t.jsonb :security_snapshot, default: {}, null: false
      t.integer :employee_count, default: 0, null: false
      t.integer :conversation_count, default: 0, null: false
      t.integer :invited_count, default: 0, null: false
      t.integer :completed_count, default: 0, null: false
      t.timestamps
    end
    add_index :companies, :slug, unique: true

    create_table :subscriptions do |t|
      t.references :company, null: false, foreign_key: true, index: { unique: true }
      t.string :plan, default: "trial", null: false
      t.string :status, default: "trial", null: false
      t.datetime :trial_ends_at
      t.datetime :current_period_ends_at
      t.integer :conversation_limit
      t.integer :conversations_used, default: 0, null: false
      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    create_table :platform_users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.string :role, default: "super_admin", null: false
      t.string :jti, null: false
      t.timestamps
    end
    add_index :platform_users, :email, unique: true
    add_index :platform_users, :jti, unique: true

    create_table :company_users do |t|
      t.references :company, null: false, foreign_key: true
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.string :role, default: "company_admin", null: false
      t.string :status, default: "active", null: false
      t.references :invited_by, foreign_key: { to_table: :company_users }
      t.string :invitation_token
      t.datetime :invitation_accepted_at
      t.datetime :onboarding_completed_at
      t.string :jti, null: false
      t.jsonb :notification_preferences, default: {}, null: false
      t.timestamps
    end
    add_index :company_users, [:company_id, :email], unique: true
    add_index :company_users, :jti, unique: true

    create_table :platform_audit_logs do |t|
      t.references :platform_user, null: false, foreign_key: true
      t.string :action, null: false
      t.string :target_type
      t.bigint :target_id
      t.jsonb :metadata, default: {}, null: false
      t.string :ip_address
      t.timestamps
    end
    add_index :platform_audit_logs, [:target_type, :target_id]
    add_index :platform_audit_logs, :created_at

    create_table :employees do |t|
      t.references :company, null: false, foreign_key: true
      t.string :phone_e164, null: false
      t.string :display_name
      t.string :department
      t.string :role_title
      t.string :seniority
      t.string :preferred_language
      t.string :participation_status, default: "invited", null: false
      t.string :onboarding_step, default: "awaiting_name", null: false
      t.datetime :consent_given_at
      t.string :consent_text_version
      t.datetime :invited_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :verified_at
      t.datetime :last_active_at
      t.datetime :last_nudged_at
      t.references :invited_by_company_user, foreign_key: { to_table: :company_users }
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :employees, :phone_e164, unique: true

    create_table :employee_access_codes do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.string :code_hint_last_two
      t.string :status, default: "active", null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :revoked_at
      t.string :issued_by_type, default: "system", null: false
      t.timestamps
    end
    add_index :employee_access_codes, [:employee_id, :status]

    create_table :notifications do |t|
      t.references :company, foreign_key: true
      t.string :recipient_type, null: false
      t.bigint :recipient_id, null: false
      t.string :notification_type, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.string :action_url
      t.jsonb :metadata, default: {}, null: false
      t.datetime :read_at
      t.datetime :emailed_at
      t.timestamps
    end
    add_index :notifications, [:recipient_type, :recipient_id]

    create_table :consent_text_versions do |t|
      t.string :version, null: false
      t.string :locale, default: "en", null: false
      t.text :body, null: false
      t.string :confirmation_keywords, array: true, default: ["YES", "I AGREE"]
      t.boolean :active, default: false, null: false
      t.timestamps
    end
    add_index :consent_text_versions, [:locale, :active]

    create_table :discovery_playbooks do |t|
      t.string :department, null: false
      t.integer :version, null: false
      t.text :prompt_block, null: false
      t.boolean :active, default: false, null: false
      t.text :notes
      t.references :created_by_platform_user, foreign_key: { to_table: :platform_users }
      t.datetime :activated_at
      t.timestamps
    end
    add_index :discovery_playbooks, [:department, :active]
  end
end
