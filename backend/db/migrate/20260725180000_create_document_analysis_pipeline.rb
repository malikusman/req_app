# frozen_string_literal: true

class CreateDocumentAnalysisPipeline < ActiveRecord::Migration[7.1]
  def change
    create_table :document_analysis_runs do |t|
      t.references :company, null: false, foreign_key: true
      t.references :triggered_by_company_user, foreign_key: { to_table: :company_users }
      t.string :run_kind, null: false, default: "full"
      t.string :status, null: false, default: "queued"
      t.string :phase
      t.string :model_tier, default: "fast"
      t.bigint :document_ids, array: true, default: [], null: false
      t.jsonb :profile_snapshot, default: {}, null: false
      t.jsonb :summary, default: {}, null: false
      t.jsonb :counters, default: {}, null: false
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :document_analysis_runs, %i[company_id status]
    add_index :document_analysis_runs, %i[company_id created_at]

    create_table :document_analysis_events do |t|
      t.references :document_analysis_run, null: false, foreign_key: true
      t.string :agent_name, null: false
      t.string :event_type, null: false, default: "step"
      t.string :phase
      t.text :message
      t.jsonb :payload, default: {}, null: false
      t.timestamps
    end
    add_index :document_analysis_events, %i[document_analysis_run_id created_at],
              name: "index_doc_analysis_events_on_run_and_created"

    create_table :company_knowledge_entries do |t|
      t.references :company, null: false, foreign_key: true
      t.references :document_analysis_run, foreign_key: true
      t.string :entry_type, null: false, default: "other"
      t.string :title, null: false
      t.text :content, null: false
      t.float :confidence, default: 0.5, null: false
      t.string :department
      t.string :status, null: false, default: "active"
      t.string :content_hash
      t.bigint :source_document_ids, array: true, default: [], null: false
      t.bigint :source_chunk_ids, array: true, default: [], null: false
      t.vector :embedding, limit: 1536
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :company_knowledge_entries, %i[company_id status]
    add_index :company_knowledge_entries, %i[company_id entry_type]
    add_index :company_knowledge_entries, %i[company_id content_hash]

    create_table :company_clarification_questions do |t|
      t.references :company, null: false, foreign_key: true
      t.references :document_analysis_run, foreign_key: true
      t.text :body, null: false
      t.string :status, null: false, default: "open"
      t.text :answer
      t.string :answer_source
      t.jsonb :citations, default: [], null: false
      t.bigint :answered_by_company_user_id
      t.bigint :dismissed_by_reviewer_user_id
      t.datetime :answered_at
      t.datetime :dismissed_at
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :company_clarification_questions, %i[company_id status]
    add_foreign_key :company_clarification_questions, :company_users,
                    column: :answered_by_company_user_id
    add_foreign_key :company_clarification_questions, :reviewer_users,
                    column: :dismissed_by_reviewer_user_id

    add_column :companies, :docs_profile_stale_at, :datetime
  end
end
