# frozen_string_literal: true

class AddUniqueIndexToCompanyMemoryFacts < ActiveRecord::Migration[7.1]
  def up
    # Dedupe any rows created by concurrent promotion runs before adding the index.
    execute <<~SQL
      DELETE FROM company_memory_facts a
      USING company_memory_facts b
      WHERE a.id > b.id
        AND a.conversation_id = b.conversation_id
        AND a.content = b.content
    SQL

    add_index :company_memory_facts, "conversation_id, md5(content)",
              unique: true,
              name: "index_memory_facts_on_conversation_and_content"
  end

  def down
    remove_index :company_memory_facts, name: "index_memory_facts_on_conversation_and_content"
  end
end
