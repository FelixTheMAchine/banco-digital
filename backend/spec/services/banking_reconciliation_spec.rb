require "rails_helper"

RSpec.describe Banking::Reconciliation do
  it "persists a preventive block and incident evidence when an out-of-band cache corruption is discovered" do
    account = Banking::Opening.open!(user: create_user)
    Banking::Operations.deposit!(user: account.user, amount_cents: 10_000, idempotency_key: SecureRandom.uuid)
    connection = ActiveRecord::Base.connection
    connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
    connection.execute("SET CONSTRAINTS ALL DEFERRED")

    # Simulate privileged corruption outside application controls, only inside the isolated test transaction.
    begin
      connection.execute("ALTER TABLE accounts DISABLE TRIGGER consistent_account_balance")
      account.update_columns(available_cents: 10_001)
    ensure
      connection.execute("ALTER TABLE accounts ENABLE TRIGGER consistent_account_balance")
    end

    result = described_class.call(account: account)
    connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
    expect(result.fetch(:reconciled)).to be(false)
    expect(result.fetch(:mismatches)).to include(account_id: account.id, ledger_cents: 10_000, cached_cents: 10_001)
    expect(account.reload.status).to eq("blocked")
    expect(account.available_cents).to eq(10_001)
    expect(account.ledger_account.balance_cents).to eq(10_000)
    expect(SecurityEvent.where(account: account, kind: "reconciliation_mismatch", severity: "high")).to exist
    expect(AuditLog.where(subject_id: account.id, action: "banking.reconciliation_mismatch")).to exist
    expect do
      Banking::Operations.withdraw!(user: account.user, amount_cents: 100, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("account_unavailable") }
  end
end
