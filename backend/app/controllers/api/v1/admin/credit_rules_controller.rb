module Api
  module V1
    module Admin
      class CreditRulesController < BaseController
        def show
          config, version = CreditRule.current_config
          render json: { credit_rule: { config: config, version: version } }
        end

        def update
          config = params.require(:config)
          raise ArgumentError unless config.is_a?(ActionController::Parameters)
          ::CreditRule.activate!(config: config.to_unsafe_h, admin: current_user)
          show
        end
      end
    end
  end
end
