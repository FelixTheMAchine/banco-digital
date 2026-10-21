require "rails_helper"

RSpec.describe "Simulated double-entry banking", type: :model do
  def open_account(user = create_user)
    Banking::Opening.open!(user: user)
  end

  def deposit(account, amount = 10_000, key = SecureRandom.uuid)
    Banking::Operations.deposit!(user: account.user, amount_cents: amount, idempotency_key: key)
  end

  def force_constraints!
    ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
  end

  it "opens one zero-balance account and one liability ledger for each customer" do
    user = create_user
    first = open_account(user)
    second = open_account(user)
    expect(first.id).to eq(second.id)
    expect(first.available_cents).to eq(0)
    expect(first.blocked_cents).to eq(0)
    expect(first.branch).to eq("0001")
    expect(first.ledger_account.kind).to eq("liability")
    force_constraints!
  end

  it "posts a deposit and withdrawal with equal debits and credits" do
    account = open_account
    deposit(account)
    withdrawal = Banking::Operations.withdraw!(user: account.user, amount_cents: 3_000, idempotency_key: SecureRandom.uuid)
    expect(account.reload.available_cents).to eq(7_000)
    expect(account.ledger_account.balance_cents).to eq(7_000)
    expect(withdrawal.ledger_entries.where(direction: "debit").sum(:amount_cents)).to eq(3_000)
    expect(withdrawal.ledger_entries.where(direction: "credit").sum(:amount_cents)).to eq(3_000)
    force_constraints!
  end

  it "moves both sides of a transfer in the same transaction" do
    source = open_account
    destination = open_account
    deposit(source)
    transfer = Banking::Operations.transfer!(user: source.user, destination_account_number: destination.number,
      amount_cents: 2_500, idempotency_key: SecureRandom.uuid, description: "Almoço fictício")
    expect(source.reload.available_cents).to eq(7_500)
    expect(destination.reload.available_cents).to eq(2_500)
    expect(transfer.transfer.source_account_id).to eq(source.id)
    expect(transfer.transfer.destination_account_id).to eq(destination.id)
    expect(transfer.public_json(account: source).fetch("direction")).to eq("debit")
    expect(transfer.public_json(account: destination).fetch("direction")).to eq("credit")
    force_constraints!
  end

  it "rejects insufficient funds without creating a partial debit" do
    source = open_account
    destination = open_account
    deposit(source, 1_000)
    count = LedgerEntry.count
    expect do
      Banking::Operations.transfer!(user: source.user, destination_account_number: destination.number,
        amount_cents: 1_001, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("insufficient_funds") }
    expect(source.reload.available_cents).to eq(1_000)
    expect(destination.reload.available_cents).to eq(0)
    expect(LedgerEntry.count).to eq(count)
  end

  it "rejects zero, negative, fractional and noninteger monetary inputs" do
    account = open_account
    [0, -100, 100.5, "100", nil, true].each do |value|
      expect { deposit(account, value) }.to raise_error(Banking::Error) { |error| expect(error.code).to eq("invalid_amount") }
    end
    expect(account.reload.available_cents).to eq(0)
    expect(account.ledger_transactions).to be_empty
  end

  it "rejects a transfer to the same account" do
    account = open_account
    expect do
      Banking::Operations.transfer!(user: account.user, destination_account_number: account.number,
        amount_cents: 100, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("same_account") }
  end

  it "rejects a nonexistent destination" do
    account = open_account
    expect do
      Banking::Operations.transfer!(user: account.user, destination_account_number: "999999999-9",
        amount_cents: 100, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("destination_not_found") }
  end

  it "returns the original posting for a repeated request without moving money again" do
    account = open_account
    key = SecureRandom.uuid
    first = deposit(account, 2_000, key)
    second = deposit(account, 2_000, key)
    expect(second.id).to eq(first.id)
    expect(account.reload.available_cents).to eq(2_000)
    expect(LedgerEntry.where(ledger_transaction_id: first.id).count).to eq(2)
  end

  it "rejects idempotency key reuse with a different amount" do
    account = open_account
    key = SecureRandom.uuid
    deposit(account, 2_000, key)
    expect { deposit(account, 2_001, key) }.to raise_error(Banking::Error) { |error| expect(error.code).to eq("idempotency_conflict") }
    expect(account.reload.available_cents).to eq(2_000)
  end

  it "returns an already posted operation even after its configured limit is lowered" do
    account = open_account
    key = SecureRandom.uuid
    original = deposit(account, 2_000, key)
    allow(FinancialRule).to receive(:fetch_integer).and_call_original
    allow(FinancialRule).to receive(:fetch_integer).with("banking.max_transaction_cents", 10_000_000).and_return(1_000)

    expect(deposit(account, 2_000, key).id).to eq(original.id)
    expect { deposit(account, 2_000) }.to raise_error(Banking::Error) { |error| expect(error.code).to eq("invalid_amount") }
    expect(account.reload.available_cents).to eq(2_000)
    expect(account.ledger_transactions.count).to eq(1)
  end

  it "rolls back the posting, account cache and entries if the credit insert crashes" do
    source = open_account
    destination = open_account
    deposit(source)
    old_transactions = LedgerTransaction.count
    old_entries = LedgerEntry.count
    allow(LedgerEntry).to receive(:create!).and_wrap_original do |method, *arguments, **keywords|
      attributes = keywords.empty? ? arguments.first : keywords
      raise ActiveRecord::StatementInvalid, "simulated database failure" if attributes.fetch(:direction) == "credit"
      method.call(*arguments, **keywords)
    end
    expect do
      ActiveRecord::Base.transaction(requires_new: true) do
        Banking::Operations.transfer!(user: source.user, destination_account_number: destination.number,
          amount_cents: 2_500, idempotency_key: SecureRandom.uuid)
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(source.reload.available_cents).to eq(10_000)
    expect(destination.reload.available_cents).to eq(0)
    expect(LedgerTransaction.count).to eq(old_transactions)
    expect(LedgerEntry.count).to eq(old_entries)
  end

  it "uses compensating entries for a reversal without modifying the original" do
    account = open_account
    original = deposit(account, 2_000)
    old_attributes = original.attributes
    reversal = Banking::Operations.reverse!(user: account.user, transaction: original, idempotency_key: SecureRandom.uuid)
    expect(account.reload.available_cents).to eq(0)
    expect(reversal.reverses_id).to eq(original.id)
    expect(original.reload.attributes).to eq(old_attributes)
    expect(LedgerEntry.where(ledger_transaction_id: [original.id, reversal.id]).count).to eq(4)
    force_constraints!
  end

  it "does not let the sender unilaterally reverse a completed transfer" do
    source = open_account
    destination = open_account
    deposit(source, 2_000)
    original = Banking::Operations.transfer!(user: source.user, destination_account_number: destination.number,
      amount_cents: 2_000, idempotency_key: SecureRandom.uuid)
    expect do
      Banking::Operations.reverse!(user: source.user, transaction: original, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("reversal_ineligible") }
    expect(source.reload.available_cents).to eq(0)
    expect(destination.reload.available_cents).to eq(2_000)
    expect(original.reversal).to be_nil
  end

  it "allows only one compensating reversal per original transaction" do
    account = open_account
    original = deposit(account, 2_000)
    Banking::Operations.reverse!(user: account.user, transaction: original, idempotency_key: SecureRandom.uuid)
    expect do
      Banking::Operations.reverse!(user: account.user, transaction: original, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("already_reversed") }
    expect(LedgerTransaction.where(reverses_id: original.id).count).to eq(1)
  end

  it "rejects unbalanced postings at the deferred PostgreSQL boundary" do
    account = open_account
    expect do
      LedgerTransaction.transaction(requires_new: true) do
        LedgerTransaction.create!(user: account.user, kind: "deposit", amount_cents: 500,
          idempotency_key: SecureRandom.uuid, request_digest: "a" * 64, completed_at: Time.current)
        force_constraints!
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(account.ledger_transactions).to be_empty
  end

  it "rejects direct account cache edits even if model callbacks are bypassed" do
    account = open_account
    expect do
      Account.transaction(requires_new: true) do
        account.update_columns(available_cents: 999)
        force_constraints!
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(account.reload.available_cents).to eq(0)
  end

  it "rejects direct SQL changes and deletions of ledger entries" do
    account = open_account
    original = deposit(account)
    entry = original.ledger_entries.first
    expect do
      LedgerEntry.transaction(requires_new: true) { LedgerEntry.where(id: entry.id).update_all(amount_cents: 1) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect do
      LedgerEntry.transaction(requires_new: true) { LedgerEntry.where(id: entry.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(original.ledger_entries.sum(:amount_cents)).to eq(20_000)
  end

  it "prevents movements after a preventive block and prevents self-unblocking" do
    account = open_account
    Banking::AccountStatus.change!(account: account, actor: account.user, status: "blocked", reason: "Teste de bloqueio")
    expect { deposit(account, 100) }.to raise_error(Banking::Error) { |error| expect(error.code).to eq("account_unavailable") }
    expect do
      Banking::AccountStatus.change!(account: account, actor: account.user, status: "active", reason: "Tentar desbloquear")
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("forbidden") }
  end

  it "classifies blocked funds and releases them only through administration without changing the ledger" do
    account = open_account
    deposit(account, 10_000)
    admin = create_user(role: "admin")
    count = LedgerEntry.count
    Banking::AccountStatus.change!(account: account, actor: account.user, status: "blocked", reason: "Bloqueio preventivo de teste")
    expect(account.reload.attributes).to include("available_cents" => 0, "blocked_cents" => 10_000)
    expect(account.ledger_account.balance_cents).to eq(10_000)
    expect(Banking::Reconciliation.call(account: account).fetch(:reconciled)).to be(true)
    Banking::AccountStatus.change!(account: account, actor: admin, status: "active", reason: "Revisão administrativa de teste")
    expect(account.reload.attributes).to include("available_cents" => 10_000, "blocked_cents" => 0)
    expect(LedgerEntry.count).to eq(count)
    expect(AuditLog.where(subject_id: account.id, action: "banking.balance_classification_changed").count).to eq(2)
    force_constraints!
  end

  it "lets the owner close an empty account and prevents further movements or reopening" do
    account = open_account
    Banking::AccountStatus.change!(account: account, actor: account.user, status: "closed", reason: "Encerramento de teste")
    expect(account.reload.status).to eq("closed")
    expect { deposit(account, 100) }.to raise_error(Banking::Error) { |error| expect(error.code).to eq("account_unavailable") }
    expect do
      Banking::AccountStatus.change!(account: account, actor: account.user, status: "active", reason: "Tentar reabrir")
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("forbidden") }
  end

  it "refuses to close an account with funds rather than trapping the owner's money" do
    account = open_account
    deposit(account, 500)
    expect do
      Banking::AccountStatus.change!(account: account, actor: account.user, status: "closed", reason: "Encerramento de teste")
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("account_not_empty") }
    expect(account.reload.status).to eq("active")
    expect(account.available_cents).to eq(500)
  end

  it "reconciles actual ledger totals rather than trusting the account cache" do
    account = open_account
    deposit(account, 2_000)
    expect(Banking::Reconciliation.call(account: account)).to eq(checked_accounts: 1, mismatches: [], reconciled: true)
    expect(Banking::BalanceHistory.average_cents(account: account)).to eq(2_000)
  end

  it "requires recent MFA for outgoing high-value operations and logs the explanation" do
    account = open_account
    deposit(account, 3_000_000)
    expect do
      Banking::Operations.withdraw!(user: account.user, amount_cents: 2_500_000, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("mfa_required") }
    expect(account.reload.available_cents).to eq(3_000_000)
    expect(SecurityEvent.where(user_id: account.user_id, kind: "operation_rejected").last.reasons).to include("mfa_required")
  end

  it "rechecks a supplied session after revocation instead of trusting its cached authentication state" do
    account = open_account
    deposit(account, 2_000)
    Auth::SessionService.issue!(user: account.user)
    session = account.user.auth_sessions.order(created_at: :desc).first
    AuthSession.where(id: session.id).update_all(revoked_at: Time.current)
    expect(session.revoked_at).to be_nil

    expect do
      Banking::Operations.withdraw!(user: account.user, amount_cents: 100,
        idempotency_key: SecureRandom.uuid, session: session)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("invalid_session") }
    expect(account.reload.available_cents).to eq(2_000)
  end

  it "rejects expired or foreign supplied sessions before moving funds" do
    account = open_account
    deposit(account, 2_000)
    Auth::SessionService.issue!(user: account.user)
    expired = account.user.auth_sessions.order(created_at: :desc).first
    expired.update!(access_expires_at: 1.second.ago)
    foreign_user = create_user
    Auth::SessionService.issue!(user: foreign_user)
    foreign = foreign_user.auth_sessions.order(created_at: :desc).first

    [expired, foreign].each do |session|
      expect do
        Banking::Operations.withdraw!(user: account.user, amount_cents: 100,
          idempotency_key: SecureRandom.uuid, session: session)
      end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("invalid_session") }
    end
    expect(account.reload.available_cents).to eq(2_000)
  end

  it "accepts a high-value debit only with MFA enabled and a current verified session" do
    account = open_account
    deposit(account, 3_000_000)
    user = account.user
    user.update!(mfa_secret: ROTP::Base32.random_base32, mfa_enabled_at: Time.current)
    Auth::SessionService.issue!(user: user, mfa_verified_at: Time.current)
    session = user.auth_sessions.order(created_at: :desc).first

    transaction = Banking::Operations.withdraw!(user: user, amount_cents: 2_500_000,
      idempotency_key: SecureRandom.uuid, session: session)
    expect(transaction.amount_cents).to eq(2_500_000)
    expect(account.reload.available_cents).to eq(500_000)
    expect(Banking::Reconciliation.call(account: account).fetch(:reconciled)).to be(true)
    force_constraints!
  end

  it "does not mistake a timestamp on a password-only session for enabled MFA" do
    account = open_account
    deposit(account, 3_000_000)
    Auth::SessionService.issue!(user: account.user)
    session = account.user.auth_sessions.order(created_at: :desc).first
    session.update!(mfa_verified_at: Time.current)

    expect do
      Banking::Operations.withdraw!(user: account.user, amount_cents: 2_500_000,
        idempotency_key: SecureRandom.uuid, session: session)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("mfa_required") }
    expect(account.reload.available_cents).to eq(3_000_000)
  end
end
