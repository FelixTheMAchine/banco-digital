class ScheduledTransferJob < ApplicationJob
  queue_as :default
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

  def perform(schedule_id)
    schedule = ScheduledTransfer.find_by(id: schedule_id)
    return unless schedule

    with_schedule_lock(schedule) do
      next unless schedule.status == "pending"
      next if schedule.scheduled_at > Time.current

      transaction = Banking::Operations.transfer!(user: schedule.user,
        destination_account_number: schedule.destination_account.number, amount_cents: schedule.amount_cents,
        description: schedule.description, idempotency_key: "scheduled-#{schedule.id}")
      schedule.update!(status: "completed", ledger_transaction: transaction)
      AuditLog.create!(user: schedule.user, action: "banking.schedule_completed", subject_id: schedule.id)
    end
  rescue Banking::Error => error
    with_schedule_lock(schedule) do
      next unless schedule.status == "pending"

      schedule.update!(status: "failed", failure_code: error.code)
      Notification.create!(user: schedule.user, kind: "schedule_failed", title: "Transferência agendada não realizada",
        body: "A operação não foi debitada. Consulte o motivo no histórico de agendamentos.")
      SecurityEvent.create!(user: schedule.user, account: schedule.source_account, kind: "scheduled_transfer_failed", severity: "medium", reasons: [error.code])
      AuditLog.create!(user: schedule.user, action: "banking.schedule_failed", subject_id: schedule.id)
    end
  end

  private

  def with_schedule_lock(schedule)
    user_ids = [schedule.user_id, schedule.source_account.user_id, schedule.destination_account.user_id].uniq
    ActiveRecord::Base.transaction(requires_new: true) do
      # Match financial operations: users first in UUID order, then the schedule.
      # Posting and the schedule outcome commit together in this transaction.
      User.where(id: user_ids).order(:id).lock.to_a
      schedule.with_lock { yield }
    end
  end
end
