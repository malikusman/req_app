# frozen_string_literal: true

class CreateReportsSchema < ActiveRecord::Migration[7.1]
  def change
    create_table :reports do |t|
      t.references :company, null: false, foreign_key: true
      t.integer :version, null: false
      t.references :previous_report, foreign_key: { to_table: :reports }
      t.string :status, default: "queued", null: false
      t.string :visibility, default: "shared_with_company", null: false
      t.string :triggered_by_type, null: false
      t.bigint :triggered_by_id, null: false
      t.references :reviewed_by_platform_user, foreign_key: { to_table: :platform_users }
      t.datetime :reviewed_at
      t.string :storage_key
      t.string :content_type, default: "application/pdf"
      t.jsonb :report_snapshot, default: {}, null: false
      t.string :share_token
      t.datetime :share_token_expires_at
      t.datetime :generated_at
      t.text :error_message
      t.timestamps
    end
    add_index :reports, [:company_id, :version], unique: true
    add_index :reports, :share_token, unique: true, where: "share_token IS NOT NULL"

    create_table :report_share_accesses do |t|
      t.references :report, null: false, foreign_key: true
      t.string :share_token, null: false
      t.string :ip_address
      t.string :user_agent
      t.datetime :accessed_at, null: false
      t.timestamps
    end
    add_index :report_share_accesses, [:report_id, :accessed_at]
  end
end
