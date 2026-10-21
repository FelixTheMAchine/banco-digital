module Api
  module V1
    class SessionsController < ApplicationController
      before_action :authenticate!

      def index
        sessions = current_user.auth_sessions.where(revoked_at: nil).where("expires_at > ?", Time.current).order(created_at: :desc)
        render json: { sessions: sessions.map { |session|
          { id: session.id, created_at: session.created_at, last_used_at: session.last_used_at,
            expires_at: session.expires_at, current: session.id == current_session.id }
        } }
      end

      def destroy
        session = current_user.auth_sessions.find(params[:id])
        ::Auth::SessionService.revoke!(session)
        AuditLog.create!(user: current_user, action: "auth.session_revoked", subject_id: session.id, request_id: request.request_id)
        head :no_content
      end
    end
  end
end
