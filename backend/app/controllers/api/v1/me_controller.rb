module Api
  module V1
    class MeController < ApplicationController
      before_action :authenticate!

      def show
        render json: { user: current_user.public_json }
      end

      def update
        current_user.with_lock do
          return render_error("forbidden", "Acesso negado.", status: :forbidden) unless UserPolicy.new(current_user, current_user).manage?

          current_user.update!(profile_params)
          audit!("user.profile_updated")
        end
        render json: { user: current_user.public_json }
      end

      def destroy
        current_user.with_lock do
          account = current_user.account
          if account && (account.available_cents.positive? || account.blocked_cents.positive? || ScheduledTransfer.exists?(user_id: current_user.id, status: "pending"))
            return render_error("account_not_empty", "Zere os saldos e cancele os agendamentos antes de desativar o cadastro.", status: :unprocessable_entity)
          end
          if account && account.status != "closed"
            Banking::AccountStatus.change!(account: account, actor: current_user, status: "closed",
              reason: "Encerramento por desativação do cadastro", request_id: request.request_id)
          end
          current_user.update!(status: "deactivated")
          current_user.auth_sessions.where(revoked_at: nil).update_all(revoked_at: Time.current)
          current_user.purpose_tokens.where(consumed_at: nil).update_all(consumed_at: Time.current)
          audit!("user.deactivated")
        end
        head :no_content
      end

      private

      def profile_params
        user = params.require(:user)
        raise ActionController::ParameterMissing, :user unless user.is_a?(ActionController::Parameters)

        user.permit(:full_name, :phone, :profession,
          :monthly_salary_cents, :other_income_cents, :monthly_expenses_cents, :existing_debts_cents,
          address: [:street, :number, :city, :state, :postal_code])
      end

      def audit!(action)
        AuditLog.create!(user: current_user, subject_id: current_user.id, action: action, request_id: request.request_id)
      end
    end
  end
end
