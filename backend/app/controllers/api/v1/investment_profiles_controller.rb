module Api
  module V1
    class InvestmentProfilesController < FinancialProductsController
      def show
        profile = InvestmentProfile.find_by!(user_id: current_user.id)
        render json: { investment_profile: profile.public_json }
      end

      def create
        answers = object_param!(:answers).permit(*Investments::Profiler::ANSWER_KEYS).to_h
        profile = Investments::Profiler.save!(user: current_user, answers: answers)
        render json: { investment_profile: profile.public_json }
      end
    end
  end
end
