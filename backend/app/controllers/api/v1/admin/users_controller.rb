module Api
  module V1
    module Admin
      class UsersController < BaseController
        def index
          rows, page = paginate(User.order(created_at: :desc))
          audit!("admin.users_viewed")
          render json: { users: rows.map { |user| user.public_json.merge("role" => user.role, "mfa_enabled" => user.mfa_enabled?) }, pagination: page }
        end
      end
    end
  end
end
