module Api
  module V1
    module Admin
      class BaseController < ApplicationController
        before_action :authenticate!
        around_action :with_verified_administrator
        rescue_from ::Banking::Error do |error|
          render_error(error.code, error.message, status: error.status, details: error.details)
        end
        rescue_from ::FinancialProducts::Error do |error|
          status = error.is_a?(::FinancialProducts::Conflict) ? :conflict : :unprocessable_entity
          render_error(error.code, error.message, status: status)
        end
        rescue_from ArgumentError do
          render_error("invalid_request", "Parâmetros administrativos inválidos.", status: :unprocessable_entity)
        end

        private

        def with_verified_administrator
          require_administrator!
          return if performed?
          # Banking services lock every involved user in UUID order; honor that order for administrative blocks too.
          ids = [current_user.id]
          if controller_name == "accounts" && %w[block unblock].include?(action_name)
            ids << Account.find(params[:id]).user_id
          end
          User.transaction do
            User.where(id: ids.uniq).order(:id).lock.to_a
            current_user.reload
            current_session.reload.lock!
            if current_session.revoked_at || current_session.access_expires_at <= Time.current || !current_user.active?
              return render_error("unauthorized", "Sessão administrativa encerrada.", status: :unauthorized)
            end
            require_administrator!
            yield unless performed?
          end
        end

        def require_administrator!
          return render_error("forbidden", "Acesso restrito à administração.", status: :forbidden) unless current_user.role == "admin"
          return render_error("mfa_required", "Ative a autenticação em duas etapas.", status: :forbidden) unless current_user.mfa_enabled?
          unless current_session.mfa_verified_at && current_session.mfa_verified_at > 5.minutes.ago
            render_error("mfa_step_up_required", "Confirme novamente seu código de segurança.", status: :forbidden)
          end
        end

        def paginate(scope)
          page = params[:page].present? ? Integer(params[:page], exception: false) : 1
          per_page = params[:per_page].present? ? Integer(params[:per_page], exception: false) : 30
          raise ArgumentError unless page && page.between?(1, 100_000) && per_page && per_page.between?(1, 100)
          count = scope.count
          [scope.limit(per_page).offset((page - 1) * per_page), { page: page, per_page: per_page, total_count: count, total_pages: (count + per_page - 1) / per_page }]
        end

        def audit!(action, subject_id: nil)
          AuditLog.create!(user: current_user, action: action, subject_id: subject_id, request_id: request.request_id)
        end

        def required_reason!
          reason = params.require(:reason)
          raise ArgumentError unless reason.is_a?(String) && reason.strip.length.between?(10, 1000)
          reason.strip
        end
      end
    end
  end
end
