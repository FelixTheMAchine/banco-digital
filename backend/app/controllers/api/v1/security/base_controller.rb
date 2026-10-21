module Api
  module V1
    module Security
      class BaseController < ApplicationController
        before_action :authenticate!
        rescue_from ::Security::MfaService::InvalidCode do
          AuditLog.create!(user: current_user, action: "security.mfa_rejected", subject_id: current_user.id, request_id: request.request_id)
          ::SecurityEvent.create!(user: current_user, kind: "mfa_rejected", severity: "medium", reasons: ["invalid_or_reused_security_confirmation"])
          render_error("invalid_mfa", "Confirmação de segurança inválida ou já utilizada.", status: :unprocessable_entity)
        end
        rescue_from ::Security::MfaService::AlreadyEnabled do
          render_error("mfa_already_enabled", "A autenticação em duas etapas já está ativa.", status: :conflict)
        end
        rescue_from ::Security::MfaService::Required do
          render_error("mfa_required", "Ative a autenticação em duas etapas.", status: :forbidden)
        end
      end
    end
  end
end
