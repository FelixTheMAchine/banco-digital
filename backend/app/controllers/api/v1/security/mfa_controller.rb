module Api
  module V1
    module Security
      class MfaController < BaseController
        def enrollment
          render json: ::Security::MfaService.start_enrollment!(user: current_user, session: current_session, password: params.require(:password))
        end

        def enable
          codes = ::Security::MfaService.enable!(user: current_user, session: current_session, code: params.require(:code))
          render json: { mfa_enabled: true, recovery_codes: codes }
        end

        def verify
          ::Security::MfaService.step_up!(user: current_user, session: current_session,
            code: params[:code], recovery_code: params[:recovery_code])
          render json: { verified: true, verified_until: Time.current + 5.minutes }
        end

        def destroy
          ::Security::MfaService.disable!(user: current_user, session: current_session, password: params.require(:password),
            code: params[:code], recovery_code: params[:recovery_code])
          head :no_content
        end
      end
    end
  end
end
