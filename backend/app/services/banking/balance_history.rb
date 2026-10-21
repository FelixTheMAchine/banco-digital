module Banking
  class BalanceHistory
    class << self
      def daily(account:, days: 30)
        return [] unless account

        days = days.to_i.clamp(1, 366)
        first_day = [Date.current - (days - 1), account.created_at.to_date].max
        entries = LedgerEntry.joins(:ledger_transaction).where(ledger_account_id: account.ledger_account.id)
        before = entries.where("ledger_transactions.completed_at < ?", first_day.beginning_of_day)
        balance = sum_balance(before)
        grouped = entries.where("ledger_transactions.completed_at >= ?", first_day.beginning_of_day)
          .group(Arel.sql("DATE(ledger_transactions.completed_at)"), :direction).sum(:amount_cents)
        (first_day..Date.current).map do |day|
          balance += grouped.fetch([day, "credit"], 0).to_i - grouped.fetch([day, "debit"], 0).to_i
          { date: day.iso8601, balance_cents: balance }
        end
      end

      def average_cents(account:, days: 90)
        history = daily(account: account, days: days)
        return 0 if history.empty?

        history.sum { |entry| entry.fetch(:balance_cents) }.div(history.length)
      end

      private

      def sum_balance(entries)
      entries.sum(Arel.sql("CASE WHEN ledger_entries.direction = 'credit' THEN ledger_entries.amount_cents ELSE -ledger_entries.amount_cents END"))
      end
    end
  end
end
