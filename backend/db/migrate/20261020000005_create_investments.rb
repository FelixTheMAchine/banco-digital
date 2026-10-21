class CreateInvestments < ActiveRecord::Migration[8.0]
  def change
    create_table :investment_profiles, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :restrict }, index: { unique: true }
      t.string :profile, null: false
      t.integer :score, null: false
      t.jsonb :answers, null: false, default: {}
      t.jsonb :recommendations, null: false, default: []
      t.bigint :emergency_target_cents, null: false
      t.bigint :available_to_invest_cents, null: false
      t.jsonb :warnings, null: false, default: []
      t.timestamps
    end
    add_check_constraint :investment_profiles, "profile IN ('conservative', 'moderate', 'aggressive') AND score BETWEEN 0 AND 100", name: "investment_profiles_valid_classification"
    add_check_constraint :investment_profiles, "emergency_target_cents >= 0 AND available_to_invest_cents >= 0", name: "investment_profiles_positive_money"
    add_check_constraint :investment_profiles, "jsonb_typeof(answers) = 'object' AND jsonb_typeof(recommendations) = 'array' AND jsonb_typeof(warnings) = 'array'", name: "investment_profiles_json_shapes"

    create_table :investment_simulations, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.bigint :initial_amount_cents, null: false
      t.bigint :monthly_contribution_cents, null: false
      t.integer :months, null: false
      t.decimal :annual_rate_percent, precision: 8, scale: 4, null: false
      t.bigint :final_cents, null: false
      t.bigint :contributed_cents, null: false
      t.bigint :earnings_cents, null: false
      t.jsonb :projection, null: false, default: []
      t.jsonb :scenarios, null: false, default: []
      t.jsonb :portfolio, null: false, default: {}
      t.timestamps
    end
    add_check_constraint :investment_simulations, "initial_amount_cents BETWEEN 0 AND 100000000 AND monthly_contribution_cents BETWEEN 0 AND 100000000 AND months BETWEEN 1 AND 600", name: "investment_simulations_input_bounds"
    add_check_constraint :investment_simulations, "annual_rate_percent BETWEEN -20 AND 50 AND final_cents BETWEEN 0 AND 9000000000000000 AND contributed_cents >= 0 AND earnings_cents = final_cents - contributed_cents", name: "investment_simulations_result_bounds"

    create_table :financial_goals, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.string :name, null: false, limit: 120
      t.bigint :target_cents, null: false
      t.date :target_date, null: false
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_check_constraint :financial_goals, "target_cents BETWEEN 1 AND 9000000000000000", name: "financial_goals_positive_target"
    add_check_constraint :financial_goals, "status IN ('active', 'completed', 'cancelled')", name: "financial_goals_valid_status"
  end
end
