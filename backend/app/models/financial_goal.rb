class FinancialGoal < ApplicationRecord
  belongs_to :user
  validates :name, presence: true, length: { minimum: 3, maximum: 120 }
  validates :status, inclusion: { in: %w[active completed cancelled] }
  validate :valid_target

  def public_json
    as_json(only: %i[id name target_cents target_date status created_at updated_at])
  end

  private

  def valid_target
    raw = target_cents_before_type_cast
    errors.add(:target_cents, :invalid) unless raw.is_a?(Integer) && raw.between?(1, FinancialProducts::Input::MAX_CENTS)
    minimum_date = created_at&.to_date || Date.current
    errors.add(:target_date, :invalid) unless target_date && target_date >= minimum_date && target_date <= Date.current + 50.years
  end
end
