class ScheduledTransfer < ApplicationRecord
  belongs_to :user
  belongs_to :source_account, class_name: "Account"
  belongs_to :destination_account, class_name: "Account"
  belongs_to :ledger_transaction, optional: true
  validates :status, inclusion: { in: %w[pending completed cancelled failed] }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :description, length: { maximum: 160 }

  def public_json
    as_json(only: %i[id amount_cents description scheduled_at status failure_code ledger_transaction_id created_at])
      .merge("destination_account_number" => destination_account.number)
  end
end
