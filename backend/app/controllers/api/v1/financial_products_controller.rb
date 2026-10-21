module Api
  module V1
    class FinancialProductsController < ApplicationController
      before_action :authenticate!

      rescue_from FinancialProducts::Error do |error|
        status = error.is_a?(FinancialProducts::Conflict) ? :conflict : :unprocessable_entity
        render_error(error.code, error.message, status: status)
      end

      private

      def object_param!(key)
        object = params.require(key)
        raise ActionController::ParameterMissing, key unless object.is_a?(ActionController::Parameters)

        object
      end
    end
  end
end
