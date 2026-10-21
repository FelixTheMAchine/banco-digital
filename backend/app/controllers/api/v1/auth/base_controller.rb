module Api
  module V1
    module Auth
      class BaseController < ApplicationController
        GENERIC_MESSAGE = "Se os dados forem válidos, você receberá as instruções.".freeze

        rescue_from ::Auth::SessionService::InvalidCredentials do
          render_error("invalid_credentials", "Credenciais inválidas ou sessão expirada.", status: :unauthorized)
        end
        rescue_from ::Auth::PurposeTokenService::InvalidToken do
          render_error("invalid_token", "Token inválido ou expirado.", status: :unprocessable_entity)
        end

        private

        def string_param!(key, maximum:)
          value = params.require(key)
          unless value.is_a?(String) && value.bytesize <= maximum
            raise ActionController::ParameterMissing, key
          end

          value
        end

        def audit!(action, user: nil, subject_id: nil)
          AuditLog.create!(action: action, user: user, subject_id: subject_id, request_id: request.request_id)
        end
      end
    end
  end
end
