module Api
  module V1
    class LoanAppealsController < FinancialProductsController
      def create
        loan = Loan.where(user_id: current_user.id).find(params[:loan_id])
        appeal = Credit::Applications.appeal!(loan: loan, user: current_user, reason: params.require(:reason))
        render json: { appeal: appeal.public_json }, status: :created
      end
    end
  end
end
