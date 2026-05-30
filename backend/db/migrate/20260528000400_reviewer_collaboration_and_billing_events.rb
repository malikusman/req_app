# frozen_string_literal: true

class ReviewerCollaborationAndBillingEvents < ActiveRecord::Migration[7.1]
  def change
    change_table :reviewer_chat_messages, bulk: true do |t|
      t.references :sender_platform_user, foreign_key: { to_table: :platform_users }
      t.string :sender_role, null: false, default: "reviewer"
      t.string :attachment_filename
      t.string :attachment_content_type
      t.bigint :attachment_byte_size
      t.string :attachment_storage_key
    end
    change_column_null :reviewer_chat_messages, :sender_reviewer_user_id, true

    create_table :billing_events do |t|
      t.references :company, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :status
      t.integer :amount_cents
      t.string :currency, default: "usd", null: false
      t.string :stripe_event_id
      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.datetime :occurred_at, null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :billing_events, :stripe_event_id, unique: true
    add_index :billing_events, %i[company_id occurred_at]
  end
end
