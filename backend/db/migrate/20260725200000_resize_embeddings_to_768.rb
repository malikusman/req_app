# frozen_string_literal: true

class ResizeEmbeddingsTo768 < ActiveRecord::Migration[7.1]
  TABLES = %w[
    document_chunks
    company_memory_facts
    company_knowledge_entries
    solution_catalog
  ].freeze

  def up
    TABLES.each do |table|
      next unless table_exists?(table)
      next unless column_exists?(table, :embedding)

      execute "UPDATE #{table} SET embedding = NULL WHERE embedding IS NOT NULL"
      execute "ALTER TABLE #{table} ALTER COLUMN embedding TYPE vector(768)"
    end
  end

  def down
    TABLES.each do |table|
      next unless table_exists?(table)
      next unless column_exists?(table, :embedding)

      execute "UPDATE #{table} SET embedding = NULL WHERE embedding IS NOT NULL"
      execute "ALTER TABLE #{table} ALTER COLUMN embedding TYPE vector(1536)"
    end
  end
end
