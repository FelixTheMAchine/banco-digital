module Api
  module V1
    module Auth
      class LoginsController < BaseController
        rescue_from ::Security::MfaService::InvalidCode do
          audit!("auth.mfa_rejected", user: @mfa_user, subject_id: @mfa_user&.id)
          ::SecurityEvent.create!(user: @mfa_user, kind: "mfa_login_rejected", severity: "medium", reasons: ["invalid_or_reused_second_factor"]) if @mfa_user
          render_error("invalid_credentials", "Credenciais inválidas ou sessão expirada.", status: :unauthorized)
        end

        rescue_from ::Security::MfaService::Required do
          render_error("mfa_required", "Informe o código de autenticação em duas etapas.", status: :unauthorized)
        end

        DUMMY_DIGEST = Argon2::Password.create("local-dummy-password-for-timing", **User::PASSWORD_OPTIONS).freeze

        def create
          email = string_param!(:email, maximum: 254).strip.downcase
          password = string_param!(:password, maximum: 512)

          user = User.find_by(email: email)
          valid_password = user ? user.authenticate(password) : Argon2::Password.verify_password(password, DUMMY_DIGEST)
          unless user && valid_password && user.active? && user.email_verified_at.present?
            audit!("auth.login_rejected")
            raise ::Auth::SessionService::InvalidCredentials
          end

          tokens = user.with_lock do
            # Recheck the password under the same lock used by password resets.
            raise ::Auth::SessionService::InvalidCredentials unless user.authenticate(password)

            verified_at = nil
            if user.mfa_enabled?
              @mfa_user = user
              if params[:otp_code].blank? && params[:recovery_code].blank?
                raise ::Security::MfaService::Required
              end
              ::Security::MfaService.verify!(user: user, code: params[:otp_code], recovery_code: params[:recovery_code])
              verified_at = Time.current
            end
            issued = ::Auth::SessionService.issue!(user: user, mfa_verified_at: verified_at)
            audit!("auth.login", user: user, subject_id: user.id)
            issued
          end
          render json: tokens
        end
      end
    end
  end
end
