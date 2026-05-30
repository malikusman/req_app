# frozen_string_literal: true

class MultiAgentFoundation < ActiveRecord::Migration[7.1]
  def change
    add_column :employees, :agent_profile, :jsonb, default: {}, null: false

    create_table :knowledge_chunks do |t|
      t.references :company, null: false, foreign_key: true
      t.string :source_type, null: false
      t.bigint :source_id, null: false
      t.text :content, null: false
      t.vector :embedding, limit: 1536
      t.jsonb :metadata, default: {}, null: false
      t.string :embedding_model
      t.datetime :embedded_at
      t.timestamps
    end

    add_index :knowledge_chunks, [:company_id, :source_type, :source_id],
              unique: true, name: "index_knowledge_chunks_on_company_source"

    create_table :agent_interrupts do |t|
      t.string :thread_id, null: false
      t.references :company, null: false, foreign_key: true
      t.references :employee, foreign_key: true
      t.references :conversation, foreign_key: true
      t.string :kind, null: false
      t.string :status, default: "pending", null: false
      t.jsonb :payload, default: {}, null: false
      t.jsonb :resolution, default: {}, null: false
      t.string :resolved_by_type
      t.bigint :resolved_by_id
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :agent_interrupts, [:company_id, :status]
    add_index :agent_interrupts, :thread_id

    create_table :agent_copilot_messages do |t|
      t.references :company, null: false, foreign_key: true
      t.references :reviewer_user, null: false, foreign_key: true
      t.string :thread_id, null: false
      t.string :role, null: false
      t.text :body, null: false
      t.jsonb :citations, default: [], null: false
      t.timestamps
    end

    add_index :agent_copilot_messages, [:reviewer_user_id, :company_id, :thread_id],
              name: "index_copilot_messages_on_reviewer_company_thread"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          CREATE INDEX IF NOT EXISTS index_document_chunks_on_embedding_hnsw
          ON document_chunks USING hnsw (embedding vector_cosine_ops)
          WITH (m = 16, ef_construction = 128);
        SQL
        execute <<~SQL.squish
          CREATE INDEX IF NOT EXISTS index_knowledge_chunks_on_embedding_hnsw
          ON knowledge_chunks USING hnsw (embedding vector_cosine_ops)
          WITH (m = 16, ef_construction = 128);
        SQL
      end

      dir.down do
        execute "DROP INDEX IF EXISTS index_document_chunks_on_embedding_hnsw;"
        execute "DROP INDEX IF EXISTS index_knowledge_chunks_on_embedding_hnsw;"
      end
    end
  end
end
