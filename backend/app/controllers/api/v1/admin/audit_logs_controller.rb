module Api
  module V1
    module Admin
      class AuditLogsController < BaseController
        def index
          rows, page = paginate(AuditLog.order(created_at: :desc))
          render json: { audit_logs: rows.map { |row| row.as_json(only: %i[id user_id action subject_id request_id created_at]) }, pagination: page }
        end
      end
    end
  end
end
