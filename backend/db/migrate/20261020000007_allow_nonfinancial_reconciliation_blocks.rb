class AllowNonfinancialReconciliationBlocks < ActiveRecord::Migration[8.0]
  def up
    execute validation_function(skip_nonfinancial_changes: true)
  end

  def down
    execute validation_function(skip_nonfinancial_changes: false)
  end

  private

  def validation_function(skip_nonfinancial_changes:)
    guard = if skip_nonfinancial_changes
      <<~SQL
        IF TG_OP = 'UPDATE' AND NEW.available_cents = OLD.available_cents AND NEW.blocked_cents = OLD.blocked_cents THEN
          RETURN NEW;
        END IF;
      SQL
    else
      ""
    end
    <<~SQL
      CREATE OR REPLACE FUNCTION validate_account_ledger_balance() RETURNS trigger AS $$
      DECLARE
        target_id uuid;
        ledger_total numeric;
        cached_total numeric;
      BEGIN
        IF TG_TABLE_NAME = 'accounts' THEN
          target_id := NEW.id;
          #{guard}
        ELSE
          SELECT account_id INTO target_id FROM ledger_accounts WHERE id = NEW.ledger_account_id;
        END IF;
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
    SQL
  end
end
