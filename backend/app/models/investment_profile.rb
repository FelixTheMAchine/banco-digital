class InvestmentProfile < ApplicationRecord
  belongs_to :user
  validates :user_id, uniqueness: true
  validates :profile, inclusion: { in: %w[conservative moderate aggressive] }
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  def public_json
    as_json(only: %i[id profile score answers recommendations emergency_target_cents available_to_invest_cents warnings updated_at])
      .merge("disclaimer" => Investments::Products::DISCLAIMER)
  end
end
