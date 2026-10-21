module Api
  module V1
    module Auth
      class RegistrationsController < BaseController
        def create
          user = nil
          User.transaction do
            user = User.create!(registration_params)
            audit!("auth.register", user: user, subject_id: user.id)
          end
          AuthenticationInstructionsJob.perform_later(email: user.email, purpose: "email_verification")
          render json: { user: user.public_json }, status: :created
        end

        private

        def registration_params
          user = params.require(:user)
          raise ActionController::ParameterMissing, :user unless user.is_a?(ActionController::Parameters)

          salary = user.require(:monthly_salary_cents)
          if salary.is_a?(ActionController::Parameters) || salary.is_a?(Array)
            raise ActionController::ParameterMissing, :monthly_salary_cents
          end
          user.permit(:full_name, :cpf, :birth_date, :email, :phone, :profession,
            :monthly_salary_cents, :other_income_cents, :monthly_expenses_cents, :existing_debts_cents,
            :password, :password_confirmation, address: [:street, :number, :city, :state, :postal_code])
        end
      end
    end
  end
end
