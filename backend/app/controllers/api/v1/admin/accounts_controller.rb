module Api
  module V1
    module Admin
      class AccountsController < BaseController
        def index
          rows, page = paginate(Account.order(created_at: :desc))
          render json: { accounts: rows.map { |account| account.public_json.merge("user_id" => account.user_id) }, pagination: page }
        end

        def block
          change_status("blocked")
        end

        def unblock
          change_status("active")
        end

        private

        def change_status(status)
          account = Account.find(params[:id])
          ::Banking::AccountStatus.change!(account: account, actor: current_user, status: status,
            reason: required_reason!, request_id: request.request_id)
          render json: { account: account.reload.public_json }
        end
      end
    end
  end
end
