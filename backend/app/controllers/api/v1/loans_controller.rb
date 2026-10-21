module Api
  module V1
    class LoansController < FinancialProductsController
      def index
        loans = Loan.where(user_id: current_user.id).order(created_at: :desc).limit(100)
        render json: { loans: loans.map(&:public_json) }
      end

      def show
        render json: { loan: Loan.where(user_id: current_user.id).find(params[:id]).public_json }
      end

      def create
        loan = Credit::Applications.submit!(user: current_user, amount_cents: params.require(:amount_cents),
          term_months: params.require(:term_months), monthly_debt_payment_cents: params[:monthly_debt_payment_cents],
          idempotency_key: request.headers["Idempotency-Key"])
        render json: { loan: loan.public_json }, status: :created
      end
    end
  end
end
