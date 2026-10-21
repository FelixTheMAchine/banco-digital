module Fraud
  class Assessment
    HISTORY_SIZE = 20
    MIN_HISTORY_SIZE = 5
    UNUSUAL_MINIMUM_CENTS = 100_000
    UNUSUAL_MULTIPLIER = 3

    class << self
      def check!(user:, account:, kind:, amount_cents:, session: nil)
        cooldown = Banking::Inputs.rule("fraud.cooldown_seconds", 300)
        cooling_down = SecurityEvent.where(user_id: user.id, kind: "temporary_operation_block").where("created_at >= ?", cooldown.seconds.ago).exists?
        attempts = SecurityEvent.where(user_id: user.id, kind: "operation_rejected").where("created_at >= ?", 1.minute.ago).count
        if cooling_down || attempts >= Banking::Inputs.rule("fraud.attempts_per_minute", 5)
          raise Banking::Error.new("temporarily_blocked", "Operações temporariamente suspensas após tentativas repetidas.", status: :forbidden,
            details: { retry_after_seconds: cooldown })
        end

        debit = %w[withdrawal transfer reversal].include?(kind)
        baseline = []
        if debit
          previous_debits = LedgerEntry.joins(:ledger_transaction).where(ledger_account_id: account.ledger_account.id, direction: "debit")
          spent = previous_debits
            .where("ledger_transactions.completed_at >= ?", Time.current.beginning_of_day).sum(:amount_cents)
          daily_limit = [account.daily_limit_cents, Banking::Inputs.rule("banking.daily_limit_cents", 5_000_000)].min
          if spent + amount_cents > daily_limit
            raise Banking::Error.new("daily_limit_exceeded", "O valor excede o limite diário disponível para saídas.")
          end
          baseline = previous_debits.order("ledger_transactions.completed_at DESC", "ledger_entries.id DESC")
            .limit(HISTORY_SIZE).pluck("ledger_entries.amount_cents")
        end

        high_value = amount_cents >= Banking::Inputs.rule("fraud.high_value_cents", 2_500_000)
        baseline_average = baseline.empty? ? 0 : baseline.sum.div(baseline.length)
        unusual = debit && baseline.length >= MIN_HISTORY_SIZE && amount_cents >= UNUSUAL_MINIMUM_CENTS &&
          amount_cents > baseline_average * UNUSUAL_MULTIPLIER
        reasons = []
        reasons << "high_value" if high_value
        reasons << "unusual_vs_recent_history" if unusual
        if debit && reasons.any? && !recent_mfa?(session, user)
          details = { reason: reasons.first, reasons: reasons, confirmation_window_seconds: 300 }
          details.merge!(baseline_average_cents: baseline_average, baseline_sample_count: baseline.length) if unusual
          raise Banking::Error.new("mfa_required", "Confirme o segundo fator antes desta operação de risco elevado.", status: :forbidden,
            details: details)
        end
        reasons
      end

      def recent_mfa?(session, user)
        return false unless user.mfa_enabled? && session && session.user_id == user.id && session.respond_to?(:mfa_verified_at)
        session.revoked_at.nil? && session.access_expires_at > Time.current && session.expires_at > Time.current &&
          session.mfa_verified_at && session.mfa_verified_at >= 5.minutes.ago
      end
    end
  end
end
