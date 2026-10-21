module Api
  module V1
    class InvestmentSimulationsController < FinancialProductsController
      def index
        simulations = InvestmentSimulation.where(user_id: current_user.id).order(created_at: :desc).limit(100)
        render json: { investment_simulations: simulations.map(&:public_json) }
      end

      def show
        render json: { investment_simulation: InvestmentSimulation.where(user_id: current_user.id).find(params[:id]).public_json }
      end

      def create
        arguments = { user: current_user, initial_amount_cents: params.require(:initial_amount_cents),
          monthly_contribution_cents: params.require(:monthly_contribution_cents), months: params.require(:months) }
        simulation = if params.key?(:allocations)
          Investments::PortfolioSimulator.save!(**arguments, allocations: allocation_params)
        else
          Investments::Simulator.save!(**arguments, annual_rate_percent: params.require(:annual_rate_percent))
        end
        render json: { investment_simulation: simulation.public_json }, status: :created
      end

      private

      def allocation_params
        allocations = params.require(:allocations)
        unless allocations.is_a?(Array) && allocations.all? { |item| item.is_a?(ActionController::Parameters) }
          raise ActionController::ParameterMissing, :allocations
        end

        allocations.map { |item| item.permit(:product_id, :allocation_percent).to_h }
      end
    end
  end
end
