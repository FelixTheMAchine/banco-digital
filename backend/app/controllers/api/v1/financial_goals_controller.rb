module Api
  module V1
    class FinancialGoalsController < FinancialProductsController
      def index
        render json: { financial_goals: scope.order(:target_date).limit(100).map(&:public_json) }
      end

      def create
        current_user.with_lock do
          goal = scope.create!(goal_params)
          audit!(goal, "created")
          render json: { financial_goal: goal.public_json }, status: :created
        end
      end

      def update
        current_user.with_lock do
          goal = scope.find(params[:id])
          goal.update!(goal_params)
          audit!(goal, "updated")
          render json: { financial_goal: goal.public_json }
        end
      end

      def destroy
        current_user.with_lock do
          goal = scope.find(params[:id])
          audit!(goal, "deleted")
          goal.destroy!
        end
        head :no_content
      end

      private

      def scope
        FinancialGoal.where(user_id: current_user.id)
      end

      def goal_params
        object_param!(:financial_goal).permit(:name, :target_cents, :target_date, :status)
      end

      def audit!(goal, action)
        AuditLog.create!(user: current_user, action: "financial_goal.#{action}", subject_id: goal.id, request_id: request.request_id)
      end
    end
  end
end
