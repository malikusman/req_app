class FenceDiscoveryStateChanges < ActiveRecord::Migration[7.1]
  def up
    require Rails.root.join("lib/discovery_schema_fence")
    execute DiscoverySchemaFence::SQL
  end

  def down
    execute 'DROP TRIGGER fence_discovery_state_changes ON conversations'
    execute 'DROP FUNCTION fence_discovery_state_changes()'
  end
end
