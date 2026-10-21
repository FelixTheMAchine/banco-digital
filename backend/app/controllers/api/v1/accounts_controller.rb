module Api
  module V1
    class AccountsController < BankingBaseController
      def show
        render json: { account: own_account.public_json }
      end

      def create
        account = Banking::Opening.open!(user: current_user, request_id: request.request_id)
        render json: { account: account.public_json }, status: :created
      end

      def deposit
        transaction = Banking::Operations.deposit!(**operation_options, amount_cents: params.require(:amount_cents), description: params[:description])
        render json: { transaction: transaction.public_json(account: own_account) }, status: :created
      end

      def withdraw
        transaction = Banking::Operations.withdraw!(**operation_options, amount_cents: params.require(:amount_cents), description: params[:description])
        render json: { transaction: transaction.public_json(account: own_account) }, status: :created
      end

      def block
        account = Banking::AccountStatus.change!(account: own_account, actor: current_user, status: "blocked",
          reason: "Bloqueio preventivo solicitado pelo titular", request_id: request.request_id)
        render json: { account: account.public_json }
      end

      def close
        account = Banking::AccountStatus.change!(account: own_account, actor: current_user, status: "closed",
          reason: "Encerramento da conta solicitado pelo titular", request_id: request.request_id)
        render json: { account: account.public_json }
      end
    end
  end
end
