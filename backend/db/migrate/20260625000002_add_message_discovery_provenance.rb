# frozen_string_literal: true

class AddMessageDiscoveryProvenance < ActiveRecord::Migration[7.1]
  def change
    add_column :messages, :agent_id, :string
    add_column :messages, :routing_decision, :jsonb, default: {}, null: false
    add_index :messages, :agent_id, where: "agent_id IS NOT NULL"
  end
end
