# frozen_string_literal: true

# Conversations with leadership (Doc 08), stored as Doc 06 §4.1 ConversationSession
# and §4.3 ConversationTurn, plus a record of every model call made for them
# (Doc 05 §21 "AI run", Doc 08 §30).
#
# These are separate from the employee interview's conversations and messages,
# which belong to an employee and are read by employee-side jobs (findings,
# signals, abandonment). Nothing employee-side reads these tables.
class CreateConversationSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_sessions do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.references :engagement_participant, null: false, foreign_key: true, index: false
      t.string :session_type, null: false, default: "KEY_PERSON"
      t.string :state, null: false, default: "NOT_STARTED"
      t.jsonb :state_history, null: false, default: []
      t.string :modality, null: false, default: "TEXT"
      t.string :language, null: false, default: "en"
      t.jsonb :state_snapshot, null: false, default: {}
      t.jsonb :limits, null: false, default: {}
      t.integer :turn_count, null: false, default: 0
      t.string :close_reason
      t.boolean :needs_review, null: false, default: false
      t.jsonb :review_reasons, null: false, default: []
      t.integer :version, null: false, default: 1
      t.datetime :started_at
      t.datetime :last_activity_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :conversation_sessions, %i[engagement_participant_id version], unique: true

    create_table :conversation_turns do |t|
      t.references :conversation_session, null: false, foreign_key: true, index: false
      t.integer :turn_index, null: false
      t.string :direction, null: false
      t.text :text, null: false
      t.text :translation
      t.string :input_mode, null: false, default: "TEXT"
      t.string :mode
      t.string :targeted_slot
      t.jsonb :routing_decision, null: false, default: {}
      t.string :slots_filled, array: true, null: false, default: []
      t.jsonb :capture
      t.boolean :is_system_notice, null: false, default: false
      t.string :fallback_reason
      t.string :client_message_id
      t.timestamps
    end
    add_index :conversation_turns, %i[conversation_session_id turn_index], unique: true
    add_index :conversation_turns, %i[conversation_session_id client_message_id], unique: true,
                                                                                  where: "client_message_id IS NOT NULL"

    create_table :ai_runs do |t|
      t.references :company, null: false, foreign_key: true, index: false
      t.references :engagement, foreign_key: true, index: false
      t.references :subject, polymorphic: true
      t.string :stage, null: false
      t.string :prompt_version
      t.string :model
      t.integer :latency_ms
      t.integer :input_tokens
      t.integer :output_tokens
      t.string :finish_reason
      t.string :status, null: false
      t.string :fallback_reason
      t.jsonb :context_classes, null: false, default: []
      t.timestamps
    end
    add_index :ai_runs, %i[company_id created_at]
    add_index :ai_runs, %i[stage created_at]
  end
end
