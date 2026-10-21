class CreateBanking < ActiveRecord::Migration[8.0]
  def up
    create_table :accounts, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :restrict }, index: { unique: true }
      t.string :number, limit: 20, null: false
      t.string :branch, limit: 4, null: false, default: "0001"
      t.string :status, null: false, default: "active"
      t.bigint :available_cents, null: false, default: 0
      t.bigint :blocked_cents, null: false, default: 0
      t.bigint :daily_limit_cents, null: false, default: 5_000_000
      t.timestamps
    end
    add_index :accounts, :number, unique: true
    add_check_constraint :accounts, "status IN ('active','blocked','closed')", name: "accounts_status"
    add_check_constraint :accounts, "branch = '0001'", name: "accounts_simulated_branch"
    %w[available_cents blocked_cents daily_limit_cents].each do |field|
      add_check_constraint :accounts, "#{field} BETWEEN 0 AND 9000000000000000", name: "accounts_#{field}_bounds"
    end

    create_table :ledger_accounts, id: :uuid do |t|
      t.references :account, type: :uuid, foreign_key: { on_delete: :restrict }, index: { unique: true }
      t.string :code, null: false
      t.string :kind, null: false
      t.datetime :created_at, null: false
    end
    add_index :ledger_accounts, :code, unique: true
    add_check_constraint :ledger_accounts, "kind IN ('asset','liability')", name: "ledger_accounts_kind"
    add_check_constraint :ledger_accounts, "(kind = 'asset' AND account_id IS NULL) OR (kind = 'liability' AND account_id IS NOT NULL)", name: "ledger_accounts_owner"

    create_table :ledger_transactions, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :restrict }
      t.string :kind, null: false
      t.bigint :amount_cents, null: false
      t.string :idempotency_key, limit: 128, null: false
      t.string :request_digest, limit: 64, null: false
      t.string :description, limit: 160, null: false, default: ""
      t.uuid :reverses_id
      t.datetime :completed_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :ledger_transactions, %i[user_id idempotency_key], unique: true, name: "ledger_user_idempotency"
    add_index :ledger_transactions, :reverses_id, unique: true
    add_index :ledger_transactions, :completed_at
    add_foreign_key :ledger_transactions, :ledger_transactions, column: :reverses_id, on_delete: :restrict
    add_check_constraint :ledger_transactions, "amount_cents BETWEEN 1 AND 9000000000000000", name: "ledger_transaction_amount"
    add_check_constraint :ledger_transactions, "kind IN ('deposit','withdrawal','transfer','reversal')", name: "ledger_transaction_kind"
    add_check_constraint :ledger_transactions, "(kind = 'reversal') = (reverses_id IS NOT NULL)", name: "ledger_reversal_reference"
    add_check_constraint :ledger_transactions, "request_digest ~ '^[0-9a-f]{64}$'", name: "ledger_request_digest"

    create_table :ledger_entries, id: :uuid do |t|
      t.references :ledger_transaction, type: :uuid, null: false, foreign_key: { on_delete: :restrict }, index: false
      t.references :ledger_account, type: :uuid, null: false, foreign_key: { on_delete: :restrict }
      t.string :direction, null: false
      t.bigint :amount_cents, null: false
      t.datetime :created_at, null: false
    end
    add_index :ledger_entries, %i[ledger_transaction_id ledger_account_id], unique: true, name: "ledger_entry_per_account"
    add_check_constraint :ledger_entries, "direction IN ('debit','credit')", name: "ledger_entry_direction"
    add_check_constraint :ledger_entries, "amount_cents BETWEEN 1 AND 9000000000000000", name: "ledger_entry_amount"

    create_table :transfers, id: :uuid do |t|
      t.references :ledger_transaction, type: :uuid, null: false, foreign_key: { on_delete: :restrict }, index: { unique: true }
      t.references :source_account, type: :uuid, null: false, foreign_key: { to_table: :accounts, on_delete: :restrict }
      t.references :destination_account, type: :uuid, null: false, foreign_key: { to_table: :accounts, on_delete: :restrict }
      t.datetime :created_at, null: false
    end
    add_check_constraint :transfers, "source_account_id <> destination_account_id", name: "transfers_distinct_accounts"

    create_table :scheduled_transfers, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :restrict }
      t.references :source_account, type: :uuid, null: false, foreign_key: { to_table: :accounts, on_delete: :restrict }
      t.references :destination_account, type: :uuid, null: false, foreign_key: { to_table: :accounts, on_delete: :restrict }
      t.references :ledger_transaction, type: :uuid, foreign_key: { on_delete: :restrict }, index: { unique: true }
      t.bigint :amount_cents, null: false
      t.string :description, limit: 160, null: false, default: ""
      t.string :idempotency_key, limit: 128, null: false
      t.string :request_digest, limit: 64, null: false
      t.datetime :scheduled_at, null: false
      t.datetime :dispatch_enqueued_at
      t.string :status, null: false, default: "pending"
      t.string :failure_code
      t.timestamps
    end
    add_index :scheduled_transfers, %i[user_id idempotency_key], unique: true, name: "schedule_user_idempotency"
    add_index :scheduled_transfers, %i[status scheduled_at]
    add_check_constraint :scheduled_transfers, "source_account_id <> destination_account_id", name: "schedules_distinct_accounts"
    add_check_constraint :scheduled_transfers, "amount_cents BETWEEN 1 AND 9000000000000000", name: "schedules_amount"
    add_check_constraint :scheduled_transfers, "status IN ('pending','completed','cancelled','failed')", name: "schedules_status"
    add_check_constraint :scheduled_transfers, "(status = 'completed') = (ledger_transaction_id IS NOT NULL)", name: "schedules_completed_ledger"

    create_table :notifications, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :restrict }
      t.string :kind, null: false
      t.string :title, limit: 150, null: false
      t.string :body, limit: 500, null: false
      t.datetime :read_at
      t.datetime :created_at, null: false
    end
    add_index :notifications, %i[user_id created_at]

    create_table :security_events, id: :uuid do |t|
      t.references :user, type: :uuid, foreign_key: { on_delete: :restrict }
      t.references :account, type: :uuid, foreign_key: { on_delete: :restrict }
      t.string :kind, null: false
      t.string :severity, null: false, default: "medium"
      t.jsonb :reasons, null: false, default: []
      t.string :status, null: false, default: "open"
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :restrict }
      t.datetime :reviewed_at
      t.string :review_reason, limit: 500
      t.datetime :created_at, null: false
    end
    add_index :security_events, %i[user_id created_at]
    add_index :security_events, %i[status created_at]
    add_check_constraint :security_events, "severity IN ('low','medium','high')", name: "security_event_severity"
    add_check_constraint :security_events, "status IN ('open','reviewed')", name: "security_event_status"
    add_check_constraint :security_events, "jsonb_typeof(reasons) = 'array'", name: "security_event_reasons"

    execute <<~SQL
      CREATE FUNCTION reject_ledger_mutation() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'ledger records are immutable; use a compensating transaction';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER immutable_ledger_transactions BEFORE UPDATE OR DELETE ON ledger_transactions
        FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
      CREATE TRIGGER immutable_ledger_entries BEFORE UPDATE OR DELETE ON ledger_entries
        FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
      CREATE TRIGGER immutable_ledger_accounts BEFORE UPDATE OR DELETE ON ledger_accounts
        FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
      CREATE TRIGGER immutable_transfers BEFORE UPDATE OR DELETE ON transfers
        FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();

      CREATE FUNCTION protect_account_identity() RETURNS trigger AS $$
      BEGIN
        IF NEW.user_id <> OLD.user_id OR NEW.number <> OLD.number OR NEW.branch <> OLD.branch THEN
          RAISE EXCEPTION 'account ownership and identifiers are immutable';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      CREATE TRIGGER immutable_account_identity BEFORE UPDATE ON accounts
        FOR EACH ROW EXECUTE FUNCTION protect_account_identity();

      CREATE FUNCTION validate_ledger_balance() RETURNS trigger AS $$
      DECLARE
        target_id uuid;
        debit_total numeric;
        credit_total numeric;
        entry_count integer;
        expected_amount bigint;
      BEGIN
        IF TG_TABLE_NAME = 'ledger_transactions' THEN target_id := NEW.id;
        ELSE target_id := NEW.ledger_transaction_id; END IF;
        SELECT amount_cents INTO expected_amount FROM ledger_transactions WHERE id = target_id;
        SELECT count(*), COALESCE(sum(amount_cents) FILTER (WHERE direction = 'debit'), 0),
          COALESCE(sum(amount_cents) FILTER (WHERE direction = 'credit'), 0)
          INTO entry_count, debit_total, credit_total FROM ledger_entries WHERE ledger_transaction_id = target_id;
        IF entry_count < 2 OR debit_total <> credit_total OR debit_total <> expected_amount THEN
          RAISE EXCEPTION 'unbalanced ledger transaction %', target_id;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE CONSTRAINT TRIGGER balanced_ledger_transaction AFTER INSERT ON ledger_transactions
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_ledger_balance();
      CREATE CONSTRAINT TRIGGER balanced_ledger_entry AFTER INSERT ON ledger_entries
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_ledger_balance();

      CREATE FUNCTION validate_account_ledger_balance() RETURNS trigger AS $$
      DECLARE
        target_id uuid;
        ledger_total numeric;
        cached_total numeric;
      BEGIN
        IF TG_TABLE_NAME = 'accounts' THEN
          target_id := NEW.id;
          IF TG_OP = 'UPDATE' AND NEW.available_cents = OLD.available_cents AND NEW.blocked_cents = OLD.blocked_cents THEN
            RETURN NEW;
          END IF;
        ELSE SELECT account_id INTO target_id FROM ledger_accounts WHERE id = NEW.ledger_account_id; END IF;
        IF target_id IS NULL THEN RETURN NEW; END IF;
        SELECT available_cents::numeric + blocked_cents::numeric INTO cached_total FROM accounts WHERE id = target_id;
        SELECT COALESCE(sum(CASE WHEN e.direction = 'credit' THEN e.amount_cents ELSE -e.amount_cents END), 0)
          INTO ledger_total FROM ledger_entries e JOIN ledger_accounts l ON l.id = e.ledger_account_id
          WHERE l.account_id = target_id;
        IF cached_total <> ledger_total THEN
          RAISE EXCEPTION 'account balance does not match ledger %', target_id;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE CONSTRAINT TRIGGER consistent_account_balance AFTER INSERT OR UPDATE ON accounts
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_account_ledger_balance();
      CREATE CONSTRAINT TRIGGER consistent_entry_account_balance AFTER INSERT ON ledger_entries
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_account_ledger_balance();
    SQL

    execute "INSERT INTO ledger_accounts (id, code, kind, created_at) VALUES (gen_random_uuid(), 'simulated_clearing', 'asset', CURRENT_TIMESTAMP)"
  end

  def down
    %w[consistent_entry_account_balance balanced_ledger_entry immutable_ledger_entries].each do |name|
      execute "DROP TRIGGER #{name} ON ledger_entries"
    end
    %w[consistent_account_balance].each { |name| execute "DROP TRIGGER #{name} ON accounts" }
    execute "DROP TRIGGER immutable_account_identity ON accounts"
    %w[balanced_ledger_transaction immutable_ledger_transactions].each { |name| execute "DROP TRIGGER #{name} ON ledger_transactions" }
    execute "DROP TRIGGER immutable_ledger_accounts ON ledger_accounts"
    execute "DROP TRIGGER immutable_transfers ON transfers"
    %w[validate_account_ledger_balance validate_ledger_balance reject_ledger_mutation protect_account_identity].each { |name| execute "DROP FUNCTION #{name}()" }
    %i[security_events notifications scheduled_transfers transfers ledger_entries ledger_transactions ledger_accounts accounts].each { |table| drop_table table }
  end
end
