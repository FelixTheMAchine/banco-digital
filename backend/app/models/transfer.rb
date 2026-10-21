class Transfer < ApplicationRecord
  belongs_to :ledger_transaction
  belongs_to :source_account, class_name: "Account"
  belongs_to :destination_account, class_name: "Account"
  validates :ledger_transaction_id, uniqueness: true
  before_update { throw :abort }
  before_destroy { throw :abort }
end
