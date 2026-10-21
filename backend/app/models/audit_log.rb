class AuditLog < ApplicationRecord
  belongs_to :user, optional: true
  validates :action, presence: true, length: { maximum: 100 }
  before_update { throw :abort }
  before_destroy { throw :abort }
end
