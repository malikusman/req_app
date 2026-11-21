class AddDurableDiscoveryTurns < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :discovery_revision, :bigint, null: false, default: 0
    add_column :conversations, :discovery_state_version, :bigint, null: false, default: 0
    create_table :employee_submissions do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :submission_id, null: false
      t.text :body, null: false
      t.timestamps
    end
    add_index :employee_submissions, [:conversation_id, :submission_id], unique: true, name: 'idx_employee_submission_identity'
    add_reference :messages, :employee_submission, foreign_key: true, index: { unique: true }
    add_reference :messages, :reply_to_message, foreign_key: { to_table: :messages }, index: { unique: true }
    add_column :messages, :delivery_status, :string
    add_column :messages, :delivery_lease_until, :datetime
    add_column :messages, :delivery_token, :string
    create_table :discovery_turns do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :source_message, null: false, foreign_key: { to_table: :messages }, index: { unique: true }
      t.string :identity, null: false
      t.text :user_message, null: false
      t.string :status, null: false, default: 'queued'
      t.bigint :base_revision
      t.string :state_digest
      t.string :lease_token
      t.datetime :lease_until
      t.datetime :deadline_at
      t.datetime :retry_at
      t.integer :attempts, null: false, default: 0
      t.string :error_code
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_index :discovery_turns, :identity, unique: true
    add_index :discovery_turns, [:status, :retry_at]
  end
end
