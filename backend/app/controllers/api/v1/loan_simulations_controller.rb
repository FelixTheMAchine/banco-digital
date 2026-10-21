module Api
  module V1
    class LoanSimulationsController < FinancialProductsController
      def create
        result = Credit::Evaluator.call(user: current_user, amount_cents: params.require(:amount_cents),
          term_months: params.require(:term_months), monthly_debt_payment_cents: params[:monthly_debt_payment_cents])
        render json: { simulation: result }
      end
    end
  end
end
