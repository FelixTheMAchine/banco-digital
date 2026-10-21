module Api
  module V1
    module Auth
      class RefreshesController < BaseController
        def create
          render json: ::Auth::SessionService.refresh!(params.require(:refresh_token))
        end
      end
    end
  end
end
