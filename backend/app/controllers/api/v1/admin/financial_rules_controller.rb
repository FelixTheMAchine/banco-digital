module Api
  module V1
    module Admin
      class FinancialRulesController < BaseController
        def show
          render_rules
        end

        def update
          rules = params.require(:rules)
          raise ArgumentError unless rules.is_a?(ActionController::Parameters) && rules.keys.size.between?(1, FinancialRule::DEFAULTS.size)
          changes = rules.to_unsafe_h
          raise ArgumentError unless (changes.keys - FinancialRule::DEFAULTS.keys).empty? && changes.values.all? { |value| value.is_a?(Integer) && value.between?(1, 1_000_000_000_000) }
          FinancialRule.transaction do
            changes.keys.sort.each do |key|
              rule = FinancialRule.find_or_create_by!(key: key) { |entry| entry.value = FinancialRule::DEFAULTS.fetch(key); entry.updated_by = current_user }
              rule.lock!
              rule.update!(value: changes.fetch(key), version: rule.version + 1, updated_by: current_user)
              audit!("admin.financial_rule_changed", subject_id: rule.id)
            end
          end
          render_rules
        end

        private

        def render_rules
          render json: { financial_rules: FinancialRule.order(:key).map(&:public_json), defaults: FinancialRule::DEFAULTS }
        end
      end
    end
  end
end
