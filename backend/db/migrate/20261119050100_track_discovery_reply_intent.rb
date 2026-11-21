class TrackDiscoveryReplyIntent < ActiveRecord::Migration[7.1]
  def change
    add_reference :discovery_turns, :reply_message, foreign_key: { to_table: :messages }
    add_index :discovery_turns, :conversation_id, unique: true, where: "status = 'processing'", name: 'idx_one_processing_discovery_turn'
  end
end
