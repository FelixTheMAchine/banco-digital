class LedgerAccount < ApplicationRecord
  belongs_to :account, optional: true
  has_many :ledger_entries, dependent: :restrict_with_exception
  validates :code, presence: true, uniqueness: true
  validates :kind, inclusion: { in: %w[asset liability] }
  before_update { throw :abort }
  before_destroy { throw :abort }

  def self.clearing!
    clearing = find_by(code: "simulated_clearing")
    unless clearing
      # Schema dumps contain structure, not this system row. ON CONFLICT avoids
      # a uniqueness-validation race when independent customers post first.
      insert_all([{ code: "simulated_clearing", kind: "asset", created_at: Time.current }],
        unique_by: :index_ledger_accounts_on_code)
      clearing = find_by!(code: "simulated_clearing")
    end
    unless clearing.kind == "asset" && clearing.account_id.nil?
      raise Banking::Error.new("ledger_integrity_error", "Conta contábil de compensação inválida.", status: :service_unavailable)
    end
    clearing
  end

  def balance_cents
    balance = ledger_entries.sum(Arel.sql("CASE WHEN ledger_entries.direction = 'credit' THEN ledger_entries.amount_cents ELSE -ledger_entries.amount_cents END"))
    kind == "asset" ? -balance : balance
  end
end
