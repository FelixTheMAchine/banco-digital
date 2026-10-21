class PurposeToken < ApplicationRecord
  belongs_to :user
  validates :purpose, inclusion: { in: %w[email_verification password_reset] }
  validates :token_digest, :expires_at, presence: true
  validates :token_digest, uniqueness: true
end
