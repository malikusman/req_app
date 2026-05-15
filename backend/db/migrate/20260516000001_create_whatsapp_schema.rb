# frozen_string_literal: true

class CreateWhatsappSchema < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_events do |t|
      t.string :provider, default: "meta_whatsapp", null: false
      t.string :external_id, null: false
      t.jsonb :payload, default: {}, null: false
      t.string :status, default: "received", null: false
      t.datetime :processed_at
      t.timestamps
    end
    add_index :webhook_events, :external_id, unique: true

    create_table :access_code_verification_attempts do |t|
      t.references :company, null: false, foreign_key: true
      t.string :phone_e164, null: false
      t.references :employee, foreign_key: true
      t.boolean :success, default: false, null: false
      t.string :failure_reason
      t.string :ip_address
      t.timestamps
    end
    add_index :access_code_verification_attempts, [:company_id, :created_at]

    create_table :employee_invitations do |t|
      t.references :company, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.references :company_user, foreign_key: true
      t.string :phone_e164, null: false
      t.uuid :batch_id
      t.string :whatsapp_template_name
      t.string :delivery_status, default: "queued", null: false
      t.string :meta_message_id
      t.datetime :sent_at
      t.text :error_message
      t.timestamps
    end

    create_table :conversations do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :status, default: "onboarding", null: false
      t.uuid :langgraph_thread_id
      t.integer :question_count, default: 0, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :last_activity_at
      t.datetime :abandoned_at
      t.string :abandon_reason
      t.jsonb :state_snapshot, default: {}, null: false
      t.timestamps
    end

    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :direction, null: false
      t.string :channel, default: "whatsapp", null: false
      t.string :message_type, null: false
      t.text :body
      t.jsonb :raw_payload, default: {}, null: false
      t.string :external_id
      t.string :processing_status, default: "ready", null: false
      t.boolean :is_discovery_question, default: false, null: false
      t.timestamps
    end
    add_index :messages, :external_id, unique: true, where: "external_id IS NOT NULL"

    create_table :employee_nudges do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :company_user, foreign_key: true
      t.references :conversation, foreign_key: true
      t.string :channel, default: "whatsapp_template", null: false
      t.string :meta_message_id
      t.datetime :sent_at, null: false
      t.timestamps
    end

    create_table :whatsapp_delivery_metrics do |t|
      t.datetime :hour_bucket, null: false
      t.string :metric_type, null: false
      t.integer :count, default: 0, null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :whatsapp_delivery_metrics, [:hour_bucket, :metric_type], unique: true,
              name: "index_whatsapp_metrics_on_hour_and_type"
  end
end
