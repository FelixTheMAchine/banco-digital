class ProtectAuditLogs < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE FUNCTION reject_audit_log_mutation() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'audit_logs are append-only';
      END;
      $$ LANGUAGE plpgsql;
      CREATE TRIGGER audit_logs_immutable
      BEFORE UPDATE OR DELETE ON audit_logs
      FOR EACH ROW EXECUTE FUNCTION reject_audit_log_mutation();
    SQL
  end

  def down
    execute "DROP TRIGGER audit_logs_immutable ON audit_logs"
    execute "DROP FUNCTION reject_audit_log_mutation()"
  end
end
