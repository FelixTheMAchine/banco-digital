module Api
  module V1
    class BankingBaseController < ApplicationController
      before_action :authenticate!

      rescue_from Banking::Error do |error|
        render_error(error.code, error.message, status: error.status, details: error.details)
      end

      private

      def own_account
        @own_account ||= Account.find_by!(user_id: current_user.id)
      end

      def idempotency_key
        request.headers["Idempotency-Key"]
      end

      def operation_options
        { user: current_user, idempotency_key: idempotency_key, session: current_session, request_id: request.request_id }
      end
    end
  end
end
