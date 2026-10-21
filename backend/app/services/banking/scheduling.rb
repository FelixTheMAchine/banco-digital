require "time"

module Banking
  class Scheduling
    class << self
      def create!(user:, destination_account_number:, amount_cents:, scheduled_at:, idempotency_key:, description: nil, request_id: nil)
        amount = Inputs.amount!(amount_cents, enforce_current_limit: false)
        number = Inputs.number!(destination_account_number)
        key = Inputs.key!(idempotency_key)
        text = Inputs.description!(description)
        time = parse_time!(scheduled_at)
        source = Account.find_by!(user_id: user.id)
        destination = Account.find_by(number: number)
        raise Error.new("destination_not_found", "Conta de destino indisponível.", status: :not_found) unless destination
        raise Error.new("same_account", "Escolha outra conta de destino.") if source.id == destination.id
        digest = Inputs.digest(amount_cents: amount, destination_id: destination.id, scheduled_at: time.utc.iso8601(6), description: text)
        schedule = ActiveRecord::Base.transaction(requires_new: true) do
          User.where(id: [user.id, destination.user_id].uniq).order(:id).lock.to_a
          accounts = Account.where(id: [source.id, destination.id]).order(:id).lock.to_a
          existing = ScheduledTransfer.find_by(user_id: user.id, idempotency_key: key)
          if existing
            raise Error.new("idempotency_conflict", "A chave já foi usada com outros dados.", status: :conflict) unless existing.request_digest == digest
            next existing
          end
          Inputs.amount!(amount)
          raise Error.new("invalid_schedule", "Agende entre um minuto e um ano a partir de agora.") unless time.between?(1.minute.from_now, 1.year.from_now)
          if amount >= Inputs.rule("fraud.high_value_cents", 2_500_000)
            raise Error.new("scheduled_high_value", "Valores elevados exigem confirmação MFA imediata e não podem ser agendados.")
          end
          unless user.reload.active? && user.email_verified_at && accounts.all? { |item| item.status == "active" } && destination.user.reload.active? && destination.user.email_verified_at
            raise Error.new("account_unavailable", "Conta indisponível para agendamento.", status: :forbidden)
          end
          created = ScheduledTransfer.create!(user: user, source_account: source, destination_account: destination,
            amount_cents: amount, scheduled_at: time, idempotency_key: key, request_digest: digest, description: text)
          AuditLog.create!(user: user, action: "banking.transfer_scheduled", subject_id: created.id, request_id: request_id)
          created
        end
        if schedule.status == "pending" && schedule.dispatch_enqueued_at.nil?
          ScheduledTransferJob.set(wait_until: schedule.scheduled_at).perform_later(schedule.id)
          schedule.update!(dispatch_enqueued_at: Time.current)
        end
        schedule
      end

      def cancel!(user:, schedule:, request_id: nil)
        raise Error.new("not_found", "Agendamento não encontrado.", status: :not_found) unless schedule.user_id == user.id
        schedule.with_lock(requires_new: true) do
          raise Error.new("schedule_not_cancellable", "O agendamento já foi processado.", status: :conflict) unless schedule.status == "pending"

          schedule.update!(status: "cancelled")
          AuditLog.create!(user: user, action: "banking.schedule_cancelled", subject_id: schedule.id, request_id: request_id)
        end
      end

      def dispatch_due!
        count = 0
        ScheduledTransfer.where(status: "pending").where("scheduled_at <= ?", Time.current)
          .where("dispatch_enqueued_at IS NULL OR dispatch_enqueued_at < ?", 5.minutes.ago).find_each do |candidate|
          schedule_id = candidate.with_lock do
            next unless candidate.status == "pending" && (candidate.dispatch_enqueued_at.nil? || candidate.dispatch_enqueued_at < 5.minutes.ago)
            candidate.update!(dispatch_enqueued_at: Time.current)
            candidate.id
          end
          next unless schedule_id

          ScheduledTransferJob.perform_later(schedule_id)
          count += 1
        end
        count
      end

      private

      def parse_time!(value)
        raise Error.new("invalid_schedule", "Use uma data ISO 8601 com fuso horário.") unless value.is_a?(String) && value.match?(/(?:Z|[+-][0-9]{2}:[0-9]{2})\z/)
        Time.iso8601(value)
      rescue ArgumentError
        raise Error.new("invalid_schedule", "Data de agendamento inválida.")
      end
    end
  end
end
