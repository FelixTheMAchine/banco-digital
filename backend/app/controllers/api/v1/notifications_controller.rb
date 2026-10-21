module Api
  module V1
    class NotificationsController < BankingBaseController
      def index
        notifications = Notification.where(user_id: current_user.id).order(created_at: :desc).limit(100)
        render json: { notifications: notifications.map(&:public_json) }
      end

      def read
        notification = Notification.find_by!(id: params[:id], user_id: current_user.id)
        notification.update!(read_at: Time.current) unless notification.read_at
        render json: { notification: notification.public_json }
      end
    end
  end
end
