class LoanInstallment < ApplicationRecord
  belongs_to :loan
  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :loan_id }
  validates :status, inclusion: { in: %w[simulated paid overdue] }
  attr_readonly :loan_id, :number, :due_date, :principal_cents, :interest_cents, :payment_cents, :balance_cents

  def public_json
    as_json(only: %i[id number due_date principal_cents interest_cents payment_cents balance_cents status])
  end
end
