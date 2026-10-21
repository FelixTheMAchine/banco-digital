module Api
  module V1
    class ScheduledTransfersController < BankingBaseController
      def index
        schedules = ScheduledTransfer.where(user_id: current_user.id).includes(:destination_account).order(created_at: :desc).limit(100)
        render json: { scheduled_transfers: schedules.map(&:public_json) }
      end

      def create
        schedule = Banking::Scheduling.create!(user: current_user, destination_account_number: params.require(:destination_account_number),
          amount_cents: params.require(:amount_cents), scheduled_at: params.require(:scheduled_at), idempotency_key: idempotency_key,
          description: params[:description], request_id: request.request_id)
        render json: { scheduled_transfer: schedule.public_json }, status: :created
      end

      def destroy
        schedule = ScheduledTransfer.find_by!(id: params[:id], user_id: current_user.id)
        Banking::Scheduling.cancel!(user: current_user, schedule: schedule, request_id: request.request_id)
        head :no_content
      end
    end
  end
end
