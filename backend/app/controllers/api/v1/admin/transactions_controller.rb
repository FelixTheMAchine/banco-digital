module Api
  module V1
    module Admin
      class TransactionsController < BaseController
        def index
          scope = LedgerTransaction.order(created_at: :desc)
          scope = scope.where(kind: params[:type]) if params[:type].present?
          rows, page = paginate(scope)
          render json: { transactions: rows.map { |row| row.as_json(only: %i[id kind amount_cents description created_at reverses_id user_id]) }, pagination: page }
        end
      end
    end
  end
end
