module Api
  module V1
    module Admin
      class OverviewController < BaseController
        def show
          render json: { overview: {
            users_count: User.count,
            accounts_count: Account.count,
            transactions_count: LedgerTransaction.count,
            open_security_events_count: SecurityEvent.where(status: "open").count,
            pending_loans_count: Loan.where(status: "pending_review").count,
            total_available_cents: Account.sum(:available_cents),
            simulation: true
          } }
        end
      end
    end
  end
end
