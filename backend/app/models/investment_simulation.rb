class InvestmentSimulation < ApplicationRecord
  belongs_to :user
  before_update { throw :abort }
  before_destroy { throw :abort }

  def public_json
    as_json(only: %i[id initial_amount_cents monthly_contribution_cents months final_cents contributed_cents earnings_cents projection scenarios portfolio created_at])
      .merge("annual_rate_percent" => annual_rate_percent.to_s("F"), "disclaimer" => Investments::Products::DISCLAIMER)
  end
end
