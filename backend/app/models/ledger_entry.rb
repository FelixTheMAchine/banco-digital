class LedgerEntry < ApplicationRecord
  belongs_to :ledger_transaction
  belongs_to :ledger_account
  validates :direction, inclusion: { in: %w[debit credit] }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  before_update { throw :abort }
  before_destroy { throw :abort }
end
