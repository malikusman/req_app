# frozen_string_literal: true

class CreateIntelligenceSchema < ActiveRecord::Migration[7.1]
  def change
    create_table :company_signals do |t|
      t.references :company, null: false, foreign_key: true
      t.string :label, null: false
      t.string :signal_type, null: false
      t.float :strength, default: 0.0, null: false
      t.string :departments, array: true, default: []
      t.integer :evidence_count, default: 1, null: false
      t.string :status, default: "emerging", null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_updated_at, null: false
      t.jsonb :strength_history, default: [], null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :company_signals, [:company_id, :signal_type, :label], unique: true, name: "index_company_signals_unique_label"

    create_table :patterns do |t|
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.float :confidence, default: 0.0, null: false
      t.string :departments, array: true, default: []
      t.string :status, default: "emerging", null: false
      t.jsonb :linked_signal_ids, default: [], null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_updated_at, null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :patterns, [:company_id, :title], unique: true

    create_table :solution_catalog do |t|
      t.string :name, null: false
      t.string :vendor
      t.string :category, null: false
      t.text :description
      t.string :website_url
      t.string :tags, array: true, default: []
      t.string :match_keywords, array: true, default: []
      t.boolean :active, default: true, null: false
      t.string :partnership_tier, default: "none"
      t.timestamps
    end

    create_table :recommendations do |t|
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.text :implementation_outline
      t.string :priority, default: "medium"
      t.string :status, default: "published", null: false
      t.jsonb :catalog_matches, default: [], null: false
      t.jsonb :related_signal_ids, default: [], null: false
      t.jsonb :related_pattern_ids, default: [], null: false
      t.string :company_feedback, default: "no_response", null: false
      t.text :company_feedback_note
      t.datetime :company_feedback_at
      t.references :company_feedback_by, foreign_key: { to_table: :company_users }
      t.timestamps
    end
    add_index :recommendations, [:company_id, :title]

    create_table :recommendation_feedbacks do |t|
      t.references :recommendation, null: false, foreign_key: true
      t.references :company_user, null: false, foreign_key: true
      t.string :feedback, null: false
      t.text :note
      t.timestamps
    end

    create_table :discovery_question_feedbacks do |t|
      t.references :company, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.references :company_user, null: false, foreign_key: true
      t.string :feedback, null: false
      t.text :note
      t.timestamps
    end
    add_index :discovery_question_feedbacks, [:message_id, :company_user_id], unique: true,
              name: "index_discovery_question_feedbacks_unique"

    create_table :insight_timeline_events do |t|
      t.references :company, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :target_type
      t.bigint :target_id
      t.string :title, null: false
      t.text :summary
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :insight_timeline_events, [:company_id, :occurred_at]
  end
end
