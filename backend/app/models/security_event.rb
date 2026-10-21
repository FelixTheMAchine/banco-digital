class SecurityEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :account, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  validates :kind, presence: true
  validates :severity, inclusion: { in: %w[low medium high] }
  validates :status, inclusion: { in: %w[open reviewed] }
  validates :review_reason, length: { maximum: 500 }

  def public_json
    as_json(only: %i[id user_id account_id kind severity reasons status reviewed_by_id reviewed_at review_reason created_at])
  end
end
