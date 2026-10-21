require "rails_helper"

RSpec.describe "Scheduled simulated transfers and fraud limits", type: :model do
  include ActiveSupport::Testing::TimeHelpers
  def account_for(user = create_user)
    Banking::Opening.open!(user: user)
  end

  def funded_source
    account = account_for
    Banking::Operations.deposit!(user: account.user, amount_cents: 10_000, idempotency_key: SecureRandom.uuid)
    account
  end

  def schedule(source, destination, amount: 1_000, time: 1.hour.from_now)
    Banking::Scheduling.create!(user: source.user, destination_account_number: destination.number,
      amount_cents: amount, scheduled_at: time.iso8601, idempotency_key: SecureRandom.uuid)
  end

  it "does not reserve or move funds when scheduling and permits cancellation before execution" do
    source = funded_source
    destination = account_for
    planned = schedule(source, destination)
    expect(planned.status).to eq("pending")
    expect(source.reload.available_cents).to eq(10_000)
    expect(destination.reload.available_cents).to eq(0)
    Banking::Scheduling.cancel!(user: source.user, schedule: planned)
    expect(planned.reload.status).to eq("cancelled")
    ScheduledTransferJob.perform_now(planned.id)
    expect(source.reload.available_cents).to eq(10_000)
    expect(destination.reload.available_cents).to eq(0)
  end

  it "requires cancellation of pending outgoing schedules before closing an empty account" do
    source = account_for
    destination = account_for
    planned = schedule(source, destination)
    expect do
      Banking::AccountStatus.change!(account: source, actor: source.user, status: "closed", reason: "Encerramento de teste")
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("account_not_empty") }
    Banking::Scheduling.cancel!(user: source.user, schedule: planned)
    Banking::AccountStatus.change!(account: source, actor: source.user, status: "closed", reason: "Encerramento de teste")
    expect(source.reload.status).to eq("closed")
  end

  it "revalidates funds and executes a due transfer once even if a job is delivered twice" do
    source = funded_source
    destination = account_for
    planned = schedule(source, destination)
    planned.update!(scheduled_at: 1.minute.ago)
    2.times { ScheduledTransferJob.perform_now(planned.id) }
    expect(planned.reload.status).to eq("completed")
    expect(source.reload.available_cents).to eq(9_000)
    expect(destination.reload.available_cents).to eq(1_000)
    expect(LedgerTransaction.where(idempotency_key: "scheduled-#{planned.id}").count).to eq(1)
    ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
  end

  it "fails a due transfer without partial movement if funds were spent after scheduling" do
    source = funded_source
    destination = account_for
    planned = schedule(source, destination, amount: 10_000)
    Banking::Operations.withdraw!(user: source.user, amount_cents: 10_000, idempotency_key: SecureRandom.uuid)
    planned.update!(scheduled_at: 1.minute.ago)
    ScheduledTransferJob.perform_now(planned.id)
    expect(planned.reload.status).to eq("failed")
    expect(planned.failure_code).to eq("insufficient_funds")
    expect(planned.ledger_transaction_id).to be_nil
    expect(destination.reload.available_cents).to eq(0)
    expect(Notification.where(user_id: source.user_id, kind: "schedule_failed")).to exist
  end

  it "does not debit blocked funds when an already scheduled transfer becomes due" do
    source = funded_source
    destination = account_for
    planned = schedule(source, destination)
    Banking::AccountStatus.change!(account: source, actor: source.user, status: "blocked", reason: "Bloqueio preventivo de teste")
    planned.update!(scheduled_at: 1.minute.ago)
    ScheduledTransferJob.perform_now(planned.id)
    expect(planned.reload.attributes).to include("status" => "failed", "failure_code" => "account_unavailable")
    expect(source.reload.attributes).to include("available_cents" => 0, "blocked_cents" => 10_000)
    expect(destination.reload.available_cents).to eq(0)
    expect(LedgerTransaction.where(idempotency_key: "scheduled-#{planned.id}")).not_to exist
    expect(Banking::Reconciliation.call.fetch(:reconciled)).to be(true)
  end

  it "recovers a due schedule whose original queue enqueue was lost" do
    source = funded_source
    destination = account_for
    planned = schedule(source, destination)
    planned.update!(scheduled_at: 1.minute.ago, dispatch_enqueued_at: 6.minutes.ago)
    clear_enqueued_jobs
    expect(Banking::Scheduling.dispatch_due!).to eq(1)
    expect(enqueued_jobs.map { |job| job.fetch(:job) }).to include(ScheduledTransferJob)
    expect(Banking::Scheduling.dispatch_due!).to eq(0)
  end

  it "returns the original scheduled operation when a retry arrives after its due time" do
    source = funded_source
    destination = account_for
    key = SecureRandom.uuid
    due = 1.hour.from_now.iso8601
    original = Banking::Scheduling.create!(user: source.user, destination_account_number: destination.number,
      amount_cents: 1_000, scheduled_at: due, idempotency_key: key)
    clear_enqueued_jobs

    travel 2.hours do
      replay = Banking::Scheduling.create!(user: source.user, destination_account_number: destination.number,
        amount_cents: 1_000, scheduled_at: due, idempotency_key: key)
      expect(replay.id).to eq(original.id)
      expect(ScheduledTransfer.where(user_id: source.user_id, idempotency_key: key).count).to eq(1)
      expect(enqueued_jobs).to be_empty
    end
    expect(source.reload.available_cents).to eq(10_000)
  end

  it "rejects past schedules and high values requiring immediate MFA" do
    source = funded_source
    destination = account_for
    expect { schedule(source, destination, time: 1.minute.ago) }.to raise_error(Banking::Error) { |error| expect(error.code).to eq("invalid_schedule") }
    expect { schedule(source, destination, amount: 2_500_000) }.to raise_error(Banking::Error) { |error| expect(error.code).to eq("scheduled_high_value") }
  end

  it "enforces cumulative daily outgoing limits" do
    source = funded_source
    source.update!(daily_limit_cents: 1_500)
    Banking::Operations.withdraw!(user: source.user, amount_cents: 1_000, idempotency_key: SecureRandom.uuid)
    expect do
      Banking::Operations.withdraw!(user: source.user, amount_cents: 501, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("daily_limit_exceeded") }
    expect(source.reload.available_cents).to eq(9_000)
  end

  it "temporarily blocks repeated failed operations with an explicit reason" do
    source = account_for
    5.times do
      expect do
        Banking::Operations.withdraw!(user: source.user, amount_cents: 100, idempotency_key: SecureRandom.uuid)
      end.to raise_error(Banking::Error)
    end
    # A valid incoming deposit also requires the temporary review window to expire.
    expect do
      Banking::Operations.deposit!(user: source.user, amount_cents: 100, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Banking::Error) { |error| expect(error.code).to eq("temporarily_blocked") }
    expect(SecurityEvent.where(user_id: source.user_id, kind: "temporary_operation_block")).to exist
  end

  it "requests fresh MFA when an outgoing amount is atypical relative to five actual prior debits" do
    source = account_for
    Banking::Operations.deposit!(user: source.user, amount_cents: 500_000, idempotency_key: SecureRandom.uuid)
    5.times { Banking::Operations.withdraw!(user: source.user, amount_cents: 1_000, idempotency_key: SecureRandom.uuid) }
    expect do
      Banking::Operations.withdraw!(user: source.user, amount_cents: 100_000, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Banking::Error) do |error|
      expect(error.code).to eq("mfa_required")
      expect(error.details).to include(baseline_average_cents: 1_000, baseline_sample_count: 5)
      expect(error.details.fetch(:reasons)).to include("unusual_vs_recent_history")
    end
    expect(source.reload.available_cents).to eq(495_000)
    event = SecurityEvent.where(user_id: source.user_id, kind: "operation_rejected").order(created_at: :desc).first
    expect(event.reasons).to include("mfa_required", "unusual_vs_recent_history")
  end

  it "does not invent a behavioral baseline for a new account" do
    source = account_for
    Banking::Operations.deposit!(user: source.user, amount_cents: 500_000, idempotency_key: SecureRandom.uuid)
    transaction = Banking::Operations.withdraw!(user: source.user, amount_cents: 100_000, idempotency_key: SecureRandom.uuid)
    expect(transaction).to be_a(LedgerTransaction)
    expect(source.reload.available_cents).to eq(400_000)
    expect(SecurityEvent.where(user_id: source.user_id, kind: "atypical_transaction")).not_to exist
  end

  it "allows an atypical outgoing amount after fresh MFA and records why confirmation was needed" do
    source = account_for
    Banking::Operations.deposit!(user: source.user, amount_cents: 500_000, idempotency_key: SecureRandom.uuid)
    5.times { Banking::Operations.withdraw!(user: source.user, amount_cents: 1_000, idempotency_key: SecureRandom.uuid) }
    user = source.user
    user.update!(mfa_secret: ROTP::Base32.random_base32, mfa_enabled_at: Time.current)
    Auth::SessionService.issue!(user: user, mfa_verified_at: Time.current)
    session = user.auth_sessions.order(created_at: :desc).first
    Banking::Operations.withdraw!(user: user, amount_cents: 100_000, idempotency_key: SecureRandom.uuid, session: session)
    expect(source.reload.available_cents).to eq(395_000)
    event = SecurityEvent.where(user_id: user.id, kind: "atypical_transaction").order(created_at: :desc).first
    expect(event.reasons).to include("unusual_vs_recent_history")
  end
end
