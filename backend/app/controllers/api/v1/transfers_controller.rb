module Api
  module V1
    class TransfersController < BankingBaseController
      def create
        transaction = Banking::Operations.transfer!(**operation_options,
          destination_account_number: params.require(:destination_account_number),
          amount_cents: params.require(:amount_cents), description: params[:description])
        render json: { transaction: transaction.public_json(account: own_account) }, status: :created
      end
    end
  end
end
