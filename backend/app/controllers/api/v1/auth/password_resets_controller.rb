module Api
  module V1
    module Auth
      class PasswordResetsController < BaseController
        def create
          AuthenticationInstructionsJob.perform_later(email: string_param!(:email, maximum: 254).strip.downcase,
            purpose: "password_reset")
          render json: { message: GENERIC_MESSAGE }, status: :accepted
        end

        def update
          ::Auth::PurposeTokenService.consume!(params.require(:token), purpose: "password_reset") do |user|
            user.update!(password: string_param!(:password, maximum: 512),
              password_confirmation: string_param!(:password_confirmation, maximum: 512))
            user.auth_sessions.where(revoked_at: nil).update_all(revoked_at: Time.current)
            audit!("auth.password_reset", user: user, subject_id: user.id)
          end
          render json: { message: "Senha atualizada." }
        end
      end
    end
  end
end
