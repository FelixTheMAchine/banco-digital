class LoanAppeal < ApplicationRecord
  belongs_to :loan
  belongs_to :user
  validates :reason, presence: true, length: { minimum: 10, maximum: 2000 }
  validates :status, inclusion: { in: %w[pending_review reviewed] }
  validate do
    errors.add(:user_id, :invalid) if loan && user_id != loan.user_id
  end

  def public_json
    as_json(only: %i[id reason status outcome created_at updated_at])
  end
end
