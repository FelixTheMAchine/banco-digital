module Banking
  class Operations
    class << self
      def deposit!(user:, amount_cents:, idempotency_key:, description: nil, session: nil, request_id: nil)
        post!(user: user, kind: "deposit", amount_cents: amount_cents, idempotency_key: idempotency_key,
          description: description, session: session, request_id: request_id)
      end

      def withdraw!(user:, amount_cents:, idempotency_key:, description: nil, session: nil, request_id: nil)
        post!(user: user, kind: "withdrawal", amount_cents: amount_cents, idempotency_key: idempotency_key,
          description: description, session: session, request_id: request_id)
      end

      def transfer!(user:, destination_account_number:, amount_cents:, idempotency_key:, description: nil, session: nil, request_id: nil)
        number = Inputs.number!(destination_account_number)
        destination = Account.find_by(number: number)
        raise Error.new("destination_not_found", "Conta de destino indisponível.", status: :not_found) unless destination

        post!(user: user, kind: "transfer", destination: destination, amount_cents: amount_cents,
          idempotency_key: idempotency_key, description: description, session: session, request_id: request_id)
      end

      def reverse!(user:, transaction:, idempotency_key:, session: nil, request_id: nil)
        raise Error.new("not_found", "Operação não encontrada.", status: :not_found) unless transaction.user_id == user.id
        unless %w[deposit withdrawal].include?(transaction.kind)
          raise Error.new("reversal_ineligible", "Somente depósitos e saques simulados próprios podem ser estornados. Transferências concluídas exigem revisão e consentimento.")
        end

        key = Inputs.key!(idempotency_key)
        request_digest = Inputs.digest(kind: "reversal", reverses_id: transaction.id)
        account_ids = transaction.ledger_entries.joins(:ledger_account).pluck("ledger_accounts.account_id").compact
        accounts = Account.where(id: account_ids).to_a
        user_ids = (accounts.map(&:user_id) + [user.id]).uniq.sort
        result = ActiveRecord::Base.transaction(requires_new: true) do
          lock_users!(user_ids)
          acting_user = User.find(user.id)
          ensure_user!(acting_user)
          session = current_session!(session, user: acting_user)
          locked_accounts = lock_accounts!(accounts.map(&:id))
          previous = previous!(user.id, key, request_digest)
          next previous if previous

          if transaction.completed_at < 24.hours.ago
            raise Error.new("reversal_expired", "O prazo de 24 horas para estorno simulado expirou.")
          end
          raise Error.new("already_reversed", "A operação já possui um estorno.", status: :conflict) if LedgerTransaction.exists?(reverses_id: transaction.id)
          locked_accounts.each { |account| ensure_account!(account) }
          debit_account = nil
          reversed_entries = transaction.ledger_entries.includes(:ledger_account).map do |entry|
            direction = entry.direction == "credit" ? "debit" : "credit"
            account = locked_accounts.find { |candidate| candidate.id == entry.ledger_account.account_id }
            if account && direction == "debit"
              debit_account = account
              ensure_funds!(account, entry.amount_cents)
            end
            [entry.ledger_account, direction, entry.amount_cents, account]
          end
          risk_reasons = if debit_account
            Fraud::Assessment.check!(user: acting_user, account: debit_account, kind: "reversal", amount_cents: transaction.amount_cents, session: session)
          else
            []
          end
          operation = LedgerTransaction.create!(user: user, kind: "reversal", amount_cents: transaction.amount_cents,
            idempotency_key: key, request_digest: request_digest, description: "Estorno de #{transaction.id}",
            reverses: transaction, completed_at: Time.current)
          reversed_entries.each do |ledger_account, direction, amount, account|
            LedgerEntry.create!(ledger_transaction: operation, ledger_account: ledger_account, direction: direction, amount_cents: amount)
            apply_balance!(account, direction, amount) if account
          end
          audit_and_notify!(operation, locked_accounts, risk_reasons, request_id)
          operation
        end
        result
      rescue Error => error
        record_rejection(user, error)
        raise
      end

      private

      def post!(user:, kind:, amount_cents:, idempotency_key:, description:, session:, request_id:, destination: nil)
        amount = Inputs.amount!(amount_cents, enforce_current_limit: false)
        key = Inputs.key!(idempotency_key)
        text = Inputs.description!(description)
        account = Account.find_by(user_id: user.id)
        raise Error.new("account_not_found", "Abra sua conta digital primeiro.", status: :not_found) unless account
        raise Error.new("same_account", "Escolha uma conta de destino diferente.") if destination&.id == account.id

        request_digest = Inputs.digest(kind: kind, amount_cents: amount, destination_id: destination&.id, description: text)
        user_ids = ([user.id] + [destination&.user_id].compact).uniq.sort
        ActiveRecord::Base.transaction(requires_new: true) do
          lock_users!(user_ids)
          acting_user = User.find(user.id)
          ensure_user!(acting_user)
          session = current_session!(session, user: acting_user)
          accounts = lock_accounts!(([account.id] + [destination&.id].compact).uniq)
          source = accounts.find { |candidate| candidate.id == account.id }
          target = accounts.find { |candidate| candidate.id == destination&.id }
          existing = previous!(user.id, key, request_digest)
          next existing if existing

          Inputs.amount!(amount)
          accounts.each { |item| ensure_account!(item) }
          ensure_user!(User.find(target.user_id)) if target
          ensure_funds!(source, amount) unless kind == "deposit"
          risk_reasons = Fraud::Assessment.check!(user: acting_user, account: source, kind: kind, amount_cents: amount, session: session)
          operation = LedgerTransaction.create!(user: user, kind: kind, amount_cents: amount, idempotency_key: key,
            request_digest: request_digest, description: text, completed_at: Time.current)
          clearing = LedgerAccount.clearing!
          entries = case kind
          when "deposit" then [[clearing, "debit", nil], [source.ledger_account, "credit", source]]
          when "withdrawal" then [[source.ledger_account, "debit", source], [clearing, "credit", nil]]
          when "transfer" then [[source.ledger_account, "debit", source], [target.ledger_account, "credit", target]]
          end
          entries.each do |ledger_account, direction, affected_account|
            LedgerEntry.create!(ledger_transaction: operation, ledger_account: ledger_account, direction: direction, amount_cents: amount)
            apply_balance!(affected_account, direction, amount) if affected_account
          end
          Transfer.create!(ledger_transaction: operation, source_account: source, destination_account: target) if kind == "transfer"
          audit_and_notify!(operation, accounts, risk_reasons, request_id)
          operation
        end
      rescue Error => error
        record_rejection(user, error)
        raise
      end

      def lock_users!(ids)
        User.where(id: ids).order(:id).lock.to_a
      end

      def lock_accounts!(ids)
        Account.where(id: ids).order(:id).lock.to_a
      end

      def ensure_user!(user)
        raise Error.new("user_unavailable", "Cadastro indisponível para operações.", status: :forbidden) unless user.active? && user.email_verified_at.present?
      end

      # HTTP authentication precedes the transaction. Recheck under the same user
      # lock used by logout/MFA changes, so an in-flight request cannot spend after
      # its session has been revoked. Trusted scheduled jobs do not carry a session.
      def current_session!(session, user:)
        return unless session

        fresh = AuthSession.where(user_id: user.id).lock.find_by(id: session.id) if session.is_a?(AuthSession)
        unless fresh && fresh.revoked_at.nil? && fresh.access_expires_at > Time.current && fresh.expires_at > Time.current
          raise Error.new("invalid_session", "A sessão foi encerrada ou expirou.", status: :unauthorized)
        end
        fresh
      end

      def ensure_account!(account)
        raise Error.new("account_unavailable", "Conta bloqueada ou encerrada.", status: :forbidden) unless account.status == "active"
      end

      def ensure_funds!(account, amount)
        raise Error.new("insufficient_funds", "Saldo disponível insuficiente.") if account.available_cents < amount
      end

      def previous!(user_id, key, request_digest)
        existing = LedgerTransaction.find_by(user_id: user_id, idempotency_key: key)
        return unless existing
        unless ActiveSupport::SecurityUtils.secure_compare(existing.request_digest, request_digest)
          raise Error.new("idempotency_conflict", "Esta chave já foi utilizada com outros dados.", status: :conflict)
        end
        existing
      end

      def apply_balance!(account, direction, amount)
        delta = direction == "credit" ? amount : -amount
        next_balance = account.available_cents + delta
        raise Error.new("balance_limit_exceeded", "A operação excederia o saldo permitido.") unless next_balance.between?(0, User::MAX_CENTS)

        account.update!(available_cents: next_balance)
      end

      def audit_and_notify!(operation, accounts, risk_reasons, request_id)
        AuditLog.create!(user_id: operation.user_id, action: "banking.#{operation.kind}", subject_id: operation.id, request_id: request_id)
        accounts.each do |account|
          Notification.create!(user_id: account.user_id, kind: "transaction", title: "Movimentação simulada registrada",
            body: "Consulte seu extrato para conferir os detalhes e o comprovante.")
        end
        return if risk_reasons.empty?

        SecurityEvent.create!(user_id: operation.user_id, account_id: accounts.find { |account| account.user_id == operation.user_id }&.id,
          kind: risk_reasons.include?("unusual_vs_recent_history") ? "atypical_transaction" : "high_value_transaction",
          severity: "high", reasons: risk_reasons)
      end

      def record_rejection(user, error)
        return unless user&.persisted?
        risk_reasons = if error.details.is_a?(Hash)
          Array(error.details[:reasons]).select { |reason| %w[high_value unusual_vs_recent_history].include?(reason) }
        else
          []
        end
        SecurityEvent.create!(user_id: user.id, account_id: Account.find_by(user_id: user.id)&.id,
          kind: "operation_rejected", severity: error.code == "mfa_required" ? "high" : "medium", reasons: [error.code, *risk_reasons])
        if error.code == "temporarily_blocked" && !SecurityEvent.where(user_id: user.id, kind: "temporary_operation_block").where("created_at >= ?", Inputs.rule("fraud.cooldown_seconds", 300).seconds.ago).exists?
          SecurityEvent.create!(user_id: user.id, account_id: Account.find_by(user_id: user.id)&.id,
            kind: "temporary_operation_block", severity: "high", reasons: ["repeated_rejected_operations"])
        end
      end
    end
  end
end
