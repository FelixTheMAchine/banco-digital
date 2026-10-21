class Account < ApplicationRecord
  belongs_to :user
  has_one :ledger_account, dependent: :restrict_with_exception
  has_many :outgoing_transfers, class_name: "Transfer", foreign_key: :source_account_id, dependent: :restrict_with_exception
  has_many :incoming_transfers, class_name: "Transfer", foreign_key: :destination_account_id, dependent: :restrict_with_exception
  validates :user_id, :number, uniqueness: true
  validates :branch, inclusion: { in: ["0001"] }
  validates :status, inclusion: { in: %w[active blocked closed] }
  validates :number, presence: true, length: { maximum: 20 }
  validates :available_cents, :blocked_cents, :daily_limit_cents,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: User::MAX_CENTS }

  def public_json
    as_json(only: %i[id number branch status available_cents blocked_cents daily_limit_cents created_at])
  end

  def ledger_transactions
    LedgerTransaction.joins(ledger_entries: :ledger_account).where(ledger_accounts: { account_id: id }).distinct
  end
end
