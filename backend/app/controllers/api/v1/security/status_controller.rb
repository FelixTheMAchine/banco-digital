module Api
  module V1
    module Security
      class StatusController < BaseController
        def show
          render json: {
            mfa_enabled: current_user.mfa_enabled?,
            recovery_codes_remaining: current_user.mfa_recovery_digests.size,
            mfa_verified_until: current_session.mfa_verified_at && current_session.mfa_verified_at + 5.minutes,
            active_sessions: current_user.auth_sessions.active.count,
            role: current_user.role
          }
        end
      end
    end
  end
end
