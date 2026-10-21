module Api
  module V1
    module Admin
      class SecurityEventsController < BaseController
        def index
          scope = SecurityEvent.order(created_at: :desc)
          scope = scope.where(status: params[:status]) if %w[open reviewed].include?(params[:status])
          rows, page = paginate(scope)
          render json: { security_events: rows.map { |row| row.as_json(only: %i[id user_id account_id kind severity reasons status reviewed_at review_reason created_at]) }, pagination: page }
        end

        def review
          event = SecurityEvent.find(params[:id])
          reason = required_reason!
          event.with_lock do
            event.update!(status: "reviewed", reviewed_by_id: current_user.id, reviewed_at: Time.current, review_reason: reason)
            audit!("admin.security_event_reviewed", subject_id: event.id)
          end
          render json: { security_event: event.as_json(only: %i[id kind severity reasons status reviewed_at review_reason]) }
        end
      end
    end
  end
end
