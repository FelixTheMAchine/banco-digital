module Api
  module V1
    module Auth
      class EmailVerificationsController < BaseController
        def create
          AuthenticationInstructionsJob.perform_later(email: string_param!(:email, maximum: 254).strip.downcase,
            purpose: "email_verification")
          render json: { message: GENERIC_MESSAGE }, status: :accepted
        end

        def update
          ::Auth::PurposeTokenService.consume!(params.require(:token), purpose: "email_verification") do |user|
            user.update!(email_verified_at: Time.current)
            audit!("auth.email_verified", user: user, subject_id: user.id)
          end
          render json: { message: "E-mail verificado." }
        end
      end
    end
  end
end
