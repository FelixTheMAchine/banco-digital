require "rails_helper"
require "timeout"

RSpec.describe "Committed PostgreSQL banking concurrency", type: :model do
  self.use_transactional_tests = false

  def reset_committed_data!
    raise "Isolated test database required" unless ActiveRecord::Base.connection_db_config.database.end_with?("_test")
    ActiveRecord::Base.connection.execute("TRUNCATE users, ledger_accounts CASCADE")
    LedgerAccount.create!(code: "simulated_clearing", kind: "asset")
  end

  before { reset_committed_data! }
  after { reset_committed_data! }

  def funded_account(amount = 10_000)
    account = Banking::Opening.open!(user: create_user)
    Banking::Operations.deposit!(user: account.user, amount_cents: amount, idempotency_key: SecureRandom.uuid)
    account
  end

  def simultaneously(*actions)
    ready = Queue.new
    start = Queue.new
    outcomes = Queue.new
    threads = actions.map do |action|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            outcomes << action.call
          rescue StandardError => error
            outcomes << error
          end
        end
      end
    end
    actions.length.times { ready.pop }
    actions.length.times { start << true }
    threads.each { |thread| raise "Concurrent operation did not finish" unless thread.join(15) }
    actions.length.times.map { outcomes.pop }
  end

  it "serializes competing withdrawals and never overdraws the account" do
    account = funded_account
    actions = Array.new(2) do
      -> { Banking::Operations.withdraw!(user: account.user, amount_cents: 8_000, idempotency_key: SecureRandom.uuid) }
    end
    outcomes = simultaneously(*actions)
    expect(outcomes.count { |result| result.is_a?(LedgerTransaction) }).to eq(1)
    expect(outcomes.grep(Banking::Error).map(&:code)).to eq(["insufficient_funds"])
    expect(account.reload.available_cents).to eq(2_000)
    expect(account.ledger_account.balance_cents).to eq(2_000)
  end

  it "bootstraps one clearing account when first deposits race after a structure-only load" do
    ActiveRecord::Base.connection.execute("TRUNCATE ledger_accounts CASCADE")
    accounts = Array.new(2) { Banking::Opening.open!(user: create_user) }
    outcomes = simultaneously(*accounts.map do |account|
      -> { Banking::Operations.deposit!(user: account.user, amount_cents: 1_000, idempotency_key: SecureRandom.uuid) }
    end)
    expect(outcomes).to all(be_a(LedgerTransaction))
    expect(LedgerAccount.where(code: "simulated_clearing", kind: "asset").count).to eq(1)
    expect(accounts.map { |account| account.reload.available_cents }).to eq([1_000, 1_000])
    expect(Banking::Reconciliation.call.fetch(:reconciled)).to be(true)
  end

  it "commits one posting for concurrent requests sharing the same idempotency key" do
    source = funded_account
    destination = Banking::Opening.open!(user: create_user)
    key = SecureRandom.uuid
    action = -> { Banking::Operations.transfer!(user: source.user, destination_account_number: destination.number,
      amount_cents: 1_000, idempotency_key: key) }
    outcomes = simultaneously(action, action)
    expect(outcomes).to all(be_a(LedgerTransaction))
    expect(outcomes.map(&:id).uniq.length).to eq(1)
    expect(source.reload.available_cents).to eq(9_000)
    expect(destination.reload.available_cents).to eq(1_000)
    expect(LedgerTransaction.where(user_id: source.user_id, idempotency_key: key).count).to eq(1)
  end

  it "handles opposing transfers with a deterministic lock order" do
    first = funded_account
    second = funded_account
    actions = [[first, second], [second, first]].map do |source, destination|
      -> do
        5.times do
          Banking::Operations.transfer!(user: source.user, destination_account_number: destination.number,
            amount_cents: 100, idempotency_key: SecureRandom.uuid)
        end
        :completed
      end
    end
    expect(simultaneously(*actions)).to eq([:completed, :completed])
    expect(first.reload.available_cents).to eq(10_000)
    expect(second.reload.available_cents).to eq(10_000)
    expect(Banking::Reconciliation.call.fetch(:reconciled)).to be(true)
  end

  it "allows cancellation holding the customer lock to win against a due job without deadlocking" do
    source = funded_account
    destination = Banking::Opening.open!(user: create_user)
    schedule = Banking::Scheduling.create!(user: source.user, destination_account_number: destination.number,
      amount_cents: 1_000, scheduled_at: 2.minutes.from_now.iso8601, idempotency_key: SecureRandom.uuid)
    schedule.update!(scheduled_at: 1.minute.ago)
    customer_locked = Queue.new
    cancel_now = Queue.new
    worker_pid = Queue.new
    outcomes = Queue.new

    canceller = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          source.user.with_lock do
            customer_locked << true
            cancel_now.pop
            Banking::Scheduling.cancel!(user: source.user, schedule: ScheduledTransfer.find(schedule.id))
          end
          outcomes << :cancelled
        rescue StandardError => error
          outcomes << error
        end
      end
    end
    Timeout.timeout(5) { customer_locked.pop }
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          worker_pid << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
          ScheduledTransferJob.new.perform(schedule.id)
          outcomes << :job_finished
        rescue StandardError => error
          outcomes << error
        end
      end
    end
    backend_pid = Timeout.timeout(5) { worker_pid.pop }
    # Wait for actual database contention, then let cancellation request the
    # schedule lock. A worker holding Schedule before User would deadlock here.
    Timeout.timeout(2) do
      loop do
        waiting = ActiveRecord::Base.connection.select_value(
          "SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(backend_pid)}")
        break if waiting == "Lock"
        sleep 0.01
      end
    end
    cancel_now << true
    [canceller, worker].each { |thread| raise "Scheduled transfer race did not finish" unless thread.join(15) }

    expect(2.times.map { outcomes.pop }).to match_array([:cancelled, :job_finished])
    expect(schedule.reload.status).to eq("cancelled")
    expect(source.reload.available_cents).to eq(10_000)
    expect(destination.reload.available_cents).to eq(0)
    expect(LedgerTransaction.where(idempotency_key: "scheduled-#{schedule.id}")).not_to exist
    expect(Banking::Reconciliation.call.fetch(:reconciled)).to be(true)
  ensure
    cancel_now << true if defined?(cancel_now) && cancel_now
    canceller&.join(5) if defined?(canceller)
    worker&.join(5) if defined?(worker)
  end

  it "commits one balanced transfer when duplicate due jobs run concurrently" do
    source = funded_account
    destination = Banking::Opening.open!(user: create_user)
    schedule = Banking::Scheduling.create!(user: source.user, destination_account_number: destination.number,
      amount_cents: 1_000, scheduled_at: 2.minutes.from_now.iso8601, idempotency_key: SecureRandom.uuid)
    schedule.update!(scheduled_at: 1.minute.ago)
    action = -> { ScheduledTransferJob.new.perform(schedule.id); :finished }

    expect(simultaneously(action, action)).to eq([:finished, :finished])
    expect(schedule.reload.status).to eq("completed")
    expect(source.reload.available_cents).to eq(9_000)
    expect(destination.reload.available_cents).to eq(1_000)
    transactions = LedgerTransaction.where(idempotency_key: "scheduled-#{schedule.id}")
    expect(transactions.count).to eq(1)
    expect(transactions.first.id).to eq(schedule.ledger_transaction_id)
    expect(transactions.first.ledger_entries.count).to eq(2)
    expect(Banking::Reconciliation.call.fetch(:reconciled)).to be(true)
  end

  it "rolls back a real PostgreSQL connection loss between the debit and credit" do
    source = funded_account
    destination = Banking::Opening.open!(user: create_user)
    transactions_before = LedgerTransaction.count
    entries_before = LedgerEntry.count
    reached_credit = Queue.new
    resume = Queue.new
    outcomes = Queue.new
    allow(LedgerEntry).to receive(:create!).and_wrap_original do |original, *arguments, **keywords|
      attributes = keywords.empty? ? arguments.first : keywords
      if Thread.current[:interrupt_financial_connection] && attributes.fetch(:direction) == "credit"
        reached_credit << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
        resume.pop
      end
      original.call(*arguments, **keywords)
    end
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Thread.current[:interrupt_financial_connection] = true
        begin
          outcomes << Banking::Operations.transfer!(user: source.user, destination_account_number: destination.number,
            amount_cents: 2_000, idempotency_key: SecureRandom.uuid)
        rescue StandardError => error
          outcomes << error
        ensure
          Thread.current[:interrupt_financial_connection] = nil
        end
      end
    end
    backend_pid = Timeout.timeout(10) { reached_credit.pop }
    # Only terminate this test's financial connection, never the database server.
    ActiveRecord::Base.connection.execute("SELECT pg_terminate_backend(#{Integer(backend_pid)})")
    resume << true
    raise "Interrupted transfer did not finish" unless worker.join(15)

    outcome = outcomes.pop
    expect(outcome).to be_a(ActiveRecord::ActiveRecordError)
    expect(source.reload.available_cents).to eq(10_000)
    expect(destination.reload.available_cents).to eq(0)
    expect(LedgerTransaction.count).to eq(transactions_before)
    expect(LedgerEntry.count).to eq(entries_before)
    expect(Banking::Reconciliation.call.fetch(:reconciled)).to be(true)
  ensure
    resume << true if defined?(resume) && resume
    worker&.join(2) if defined?(worker)
  end

  it "does not let a deposit reversal race a withdrawal into a negative balance" do
    source = funded_account(5_000)
    original = source.ledger_transactions.find_by!(kind: "deposit")
    outcomes = simultaneously(
      -> { Banking::Operations.reverse!(user: source.user, transaction: original, idempotency_key: SecureRandom.uuid) },
      -> { Banking::Operations.withdraw!(user: source.user, amount_cents: 5_000, idempotency_key: SecureRandom.uuid) }
    )
    expect(outcomes.count { |result| result.is_a?(LedgerTransaction) }).to eq(1)
    expect(outcomes.grep(Banking::Error).map(&:code)).to eq(["insufficient_funds"])
    expect(source.reload.available_cents).to eq(0)
    expect(Banking::Reconciliation.call.fetch(:reconciled)).to be(true)
  end
end
