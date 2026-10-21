module Api
  module V1
    class InvestmentProductsController < FinancialProductsController
      def index
        render json: { products: Investments::Products.list, disclaimer: Investments::Products::DISCLAIMER }
      end
    end
  end
end
