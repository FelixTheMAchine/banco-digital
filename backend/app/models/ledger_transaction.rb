class LedgerTransaction < ApplicationRecord
  belongs_to :user
  belongs_to :reverses, class_name: "LedgerTransaction", optional: true
  has_one :reversal, class_name: "LedgerTransaction", foreign_key: :reverses_id
  has_many :ledger_entries, dependent: :restrict_with_exception
  has_one :transfer, dependent: :restrict_with_exception
  validates :kind, inclusion: { in: %w[deposit withdrawal transfer reversal] }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :description, length: { maximum: 160 }
  validates :idempotency_key, uniqueness: { scope: :user_id }
  before_update { throw :abort }
  before_destroy { throw :abort }

  def public_json(account: nil)
    entry = account && ledger_entries.joins(:ledger_account).find_by(ledger_accounts: { account_id: account.id })
    result = as_json(only: %i[id kind amount_cents description completed_at created_at reverses_id])
    result.merge!("status" => "posted", "direction" => entry&.direction, "reversed_by_id" => reversal&.id)
    if transfer
      result["source_account_number"] = transfer.source_account.number
      result["destination_account_number"] = transfer.destination_account.number
    end
    result
  end

  def receipt_json(account:)
    public_json(account: account).merge("simulation" => true, "currency" => "BRL", "institution" => "Aurora — banco simulado",
      "account_number" => account.number, "branch" => account.branch, "reference" => id)
  end
end
