module Api
  module V1
    module Auth
      class LogoutsController < BaseController
        before_action :authenticate!

        def destroy
          ::Auth::SessionService.revoke!(current_session)
          audit!("auth.logout", user: current_user, subject_id: current_session.id)
          head :no_content
        end
      end
    end
  end
end
