module Banking
  class AccountStatus
    def self.change!(account:, actor:, status:, reason:, request_id: nil)
      unless %w[active blocked closed].include?(status) && reason.is_a?(String) && reason.strip.length.between?(3, 300)
        raise Error.new("invalid_status_change", "Informe um status e uma justificativa válidos.")
      end
      unless actor.role == "admin" || (actor.id == account.user_id && %w[blocked closed].include?(status))
        raise Error.new("forbidden", "Acesso negado.", status: :forbidden)
      end

      ActiveRecord::Base.transaction(requires_new: true) do
        User.where(id: [actor.id, account.user_id].uniq).order(:id).lock.to_a
        actor.reload
        account.lock!
        unless actor.active? && (actor.role == "admin" || (actor.id == account.user_id && %w[blocked closed].include?(status)))
          raise Error.new("forbidden", "Acesso negado.", status: :forbidden)
        end
        if account.status == "closed" && status != "closed"
          raise Error.new("account_closed", "Uma conta encerrada não pode ser reativada.")
        end
        if status == "closed" && (account.available_cents.nonzero? || account.blocked_cents.nonzero? || ScheduledTransfer.exists?(source_account_id: account.id, status: "pending"))
          raise Error.new("account_not_empty", "Para encerrar a conta, zere os saldos e cancele os agendamentos.")
        end
        before_available = account.available_cents
        before_blocked = account.blocked_cents
        attributes = { status: status }
        # These buckets classify the same customer liability. The total and
        # every ledger entry remain unchanged; this is not a balance adjustment.
        if status == "blocked"
          attributes.merge!(available_cents: 0, blocked_cents: before_available + before_blocked)
        elsif status == "active"
          attributes.merge!(available_cents: before_available + before_blocked, blocked_cents: 0)
        end
        account.update!(attributes)
        AuditLog.create!(user: actor, action: "banking.account_#{status}", subject_id: account.id, request_id: request_id)
        if before_available != account.available_cents || before_blocked != account.blocked_cents
          AuditLog.create!(user: actor, action: "banking.balance_classification_changed", subject_id: account.id, request_id: request_id)
        end
        SecurityEvent.create!(user_id: account.user_id, account: account, kind: "account_status_changed", severity: "medium",
          reasons: ["status:#{status}", "actor_role:#{actor.role}", "justification:#{reason.strip}",
            "available_before_cents:#{before_available}", "blocked_before_cents:#{before_blocked}",
            "available_after_cents:#{account.available_cents}", "blocked_after_cents:#{account.blocked_cents}"])
        label = { "active" => "ativa", "blocked" => "bloqueada", "closed" => "encerrada" }.fetch(status)
        Notification.create!(user_id: account.user_id, kind: "account_status", title: "Status da conta atualizado",
          body: "Sua conta está #{label}. Consulte o atendimento simulado para revisão.")
        account
      end
    end
  end
end
