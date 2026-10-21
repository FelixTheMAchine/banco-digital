class Loan < ApplicationRecord
  belongs_to :user
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_many :loan_installments, dependent: :restrict_with_exception
  has_many :loan_appeals, dependent: :restrict_with_exception
  validates :status, inclusion: { in: %w[pending_review rejected approved reviewed_rejected] }
  validates :idempotency_key, presence: true, uniqueness: { scope: :user_id }
  validates :review_reason, length: { maximum: 2000 }, allow_nil: true
  attr_readonly :amount_cents, :term_months, :monthly_rate, :installment_cents, :total_cents,
    :eligibility_snapshot, :rule_version, :user_id, :idempotency_key, :request_digest

  def public_json
    as_json(only: %i[id amount_cents term_months installment_cents total_cents status eligibility_snapshot
      rule_version created_at reviewed_at review_reason]).merge(
      "monthly_rate_percent" => (monthly_rate * 100).to_s("F"),
      "simulation" => true,
      "installments" => loan_installments.order(:number).map(&:public_json),
      "appeals" => loan_appeals.order(:created_at).map(&:public_json)
    )
  end
end
