module DiscoverySchemaFence
  SQL = <<~SQL.freeze
    CREATE OR REPLACE FUNCTION fence_discovery_state_changes() RETURNS trigger AS $$
    BEGIN
      IF NEW.state_snapshot IS DISTINCT FROM OLD.state_snapshot
        OR NEW.status IS DISTINCT FROM OLD.status
        OR NEW.question_count IS DISTINCT FROM OLD.question_count THEN
        NEW.discovery_revision := GREATEST(NEW.discovery_revision, OLD.discovery_revision + 1);
        NEW.discovery_state_version := GREATEST(NEW.discovery_state_version, OLD.discovery_state_version + 1);
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    DROP TRIGGER IF EXISTS fence_discovery_state_changes ON conversations;
    CREATE TRIGGER fence_discovery_state_changes BEFORE UPDATE ON conversations
      FOR EACH ROW EXECUTE FUNCTION fence_discovery_state_changes();
  SQL
end
