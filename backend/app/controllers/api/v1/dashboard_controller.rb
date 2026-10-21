module Api
  module V1
    class DashboardController < BankingBaseController
      def show
        account = Account.find_by(user_id: current_user.id)
        unless account
          return render json: { account: nil, month_income_cents: 0, month_expenses_cents: 0, evolution: [], recent_transactions: [], alerts: ["Abra sua conta digital simulada para começar."] }
        end
        entries = LedgerEntry.joins(:ledger_transaction).where(ledger_account_id: account.ledger_account.id)
          .where("ledger_transactions.completed_at >= ?", Time.current.beginning_of_month)
        recent = account.ledger_transactions.order(completed_at: :desc, id: :desc).limit(5)
        alerts = []
        alerts << "Sua conta está bloqueada para movimentações. Solicite revisão administrativa." if account.status == "blocked"
        alerts << "Seu saldo cobre menos de um mês das despesas declaradas." if account.available_cents < current_user.monthly_expenses_cents
        alerts << "Há eventos de segurança pendentes de revisão." if SecurityEvent.exists?(user_id: current_user.id, status: "open", severity: "high")
        render json: { account: account.public_json, month_income_cents: entries.where(direction: "credit").sum(:amount_cents),
          month_expenses_cents: entries.where(direction: "debit").sum(:amount_cents), evolution: Banking::BalanceHistory.daily(account: account, days: 30),
          recent_transactions: recent.map { |item| item.public_json(account: account) }, alerts: alerts }
      end
    end
  end
end
