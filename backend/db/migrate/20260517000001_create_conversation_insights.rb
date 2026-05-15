# frozen_string_literal: true

class CreateConversationInsights < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_insights do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :message, foreign_key: true
      t.integer :turn_number, null: false
      t.string :insight_type, default: "turn_summary", null: false
      t.text :summary
      t.jsonb :structured_data, default: {}, null: false
      t.timestamps
    end

    add_index :conversation_insights, [:conversation_id, :turn_number]
  end
end
