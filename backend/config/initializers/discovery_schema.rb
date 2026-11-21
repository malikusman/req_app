# Keep the PostgreSQL revision fence when a new database is loaded from schema.rb.
require Rails.root.join('lib/discovery_schema_fence')

module DiscoveryFenceSchemaDump
  def trailer(stream)
    if @connection.column_exists?(:conversations, :discovery_revision)
      stream.puts "  # Discovery state fencing must survive db:schema:load."
      stream.puts "  execute <<~SQL"
      DiscoverySchemaFence::SQL.each_line { |line| stream.print("    #{line}") }
      stream.puts "  SQL"
    end
    super
  end
end

ActiveRecord::SchemaDumper.prepend(DiscoveryFenceSchemaDump)
