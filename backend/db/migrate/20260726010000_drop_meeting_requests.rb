# frozen_string_literal: true

class DropMeetingRequests < ActiveRecord::Migration[7.1]
  def up
    if table_exists?(:meeting_requests)
      remove_foreign_key :meeting_requests, :companies if foreign_key_exists?(:meeting_requests, :companies)
      remove_foreign_key :meeting_requests, column: :approved_by_company_user_id if foreign_key_exists?(:meeting_requests, column: :approved_by_company_user_id)
      remove_foreign_key :meeting_requests, :reports if foreign_key_exists?(:meeting_requests, :reports)
      remove_foreign_key :meeting_requests, :reviewer_outreaches if foreign_key_exists?(:meeting_requests, :reviewer_outreaches)
      remove_foreign_key :meeting_requests, :reviewer_users if foreign_key_exists?(:meeting_requests, :reviewer_users)
      drop_table :meeting_requests
    end

    # Legacy outreaches created for meeting asks — keep as clarifications so purpose validation stays valid.
    execute <<~SQL.squish if table_exists?(:reviewer_outreaches)
      UPDATE reviewer_outreaches
      SET purpose = 'clarification'
      WHERE purpose = 'meeting_request'
    SQL
  end

  def down
    create_table :meeting_requests do |t|
      t.references :company, null: false, foreign_key: true
      t.references :report, foreign_key: true
      t.references :reviewer_user, null: false, foreign_key: true
      t.references :reviewer_outreach, foreign_key: true
      t.text :purpose, null: false
      t.string :desired_roles, array: true, default: []
      t.integer :duration_minutes, default: 30
      t.string :urgency, default: "normal"
      t.jsonb :proposed_windows, null: false, default: []
      t.string :status, null: false, default: "pending_admin"
      t.bigint :approved_by_company_user_id
      t.jsonb :selected_participant_ids, null: false, default: []
      t.datetime :scheduled_at
      t.string :meeting_link
      t.text :admin_note
      t.text :outcome_note
      t.jsonb :audit_trail, null: false, default: []
      t.timestamps
    end

    add_foreign_key :meeting_requests, :company_users, column: :approved_by_company_user_id
  end
end
